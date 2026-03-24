import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Content-Type": "application/json",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "Supabase environment is not configured." }, 500);
  }

  const vapidConfig = await ensureVapidConfig();

  if (request.method === "GET") {
    return jsonResponse({
      publicKey: vapidConfig.publicKey,
      subject: vapidConfig.subject,
    });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const payload = await request.json().catch(() => null);
  const messageId = payload?.record?.id;
  if (!messageId) {
    return jsonResponse({ ok: true, skipped: "missing_message_id" });
  }

  const { data: claimed, error: claimError } = await supabase.rpc("app_claim_push_dispatch", {
    p_message_id: messageId,
  });
  if (claimError) {
    console.error("Claim push dispatch failed", claimError);
    return jsonResponse({ error: "Failed to claim push dispatch." }, 500);
  }

  if (!claimed) {
    return jsonResponse({ ok: true, skipped: "already_dispatched" });
  }

  const { data: deliveries, error: deliveriesError } = await supabase.rpc("app_get_push_delivery_batch", {
    p_message_id: messageId,
  });
  if (deliveriesError) {
    console.error("Load push delivery batch failed", deliveriesError);
    return jsonResponse({ error: "Failed to load push delivery batch." }, 500);
  }

  const batch = Array.isArray(deliveries) ? deliveries : [];
  if (batch.length === 0) {
    return jsonResponse({ ok: true, sent: 0, removed: 0, failed: 0 });
  }

  webpush.setVapidDetails(
    vapidConfig.subject,
    vapidConfig.publicKey,
    vapidConfig.privateKey,
  );

  let sent = 0;
  let removed = 0;
  let failed = 0;

  for (const delivery of batch) {
    try {
      await webpush.sendNotification(
        delivery.subscription,
        JSON.stringify({
          title: delivery.title,
          body: delivery.body,
          tag: delivery.tag,
          data: delivery.data,
        }),
      );
      sent += 1;
    } catch (error) {
      const statusCode = typeof error?.statusCode === "number" ? error.statusCode : null;
      if (statusCode === 404 || statusCode === 410) {
        await removeSubscription(delivery.endpoint);
        removed += 1;
        continue;
      }

      failed += 1;
      console.error("Web push send failed", {
        endpoint: delivery.endpoint,
        statusCode,
        message: error?.message ?? String(error),
      });
    }
  }

  return jsonResponse({
    ok: true,
    sent,
    removed,
    failed,
  });
});

async function ensureVapidConfig() {
  const { data: existing, error } = await supabase
    .from("push_vapid_config")
    .select("public_key, private_key, subject")
    .eq("id", true)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (existing?.public_key && existing?.private_key && existing?.subject) {
    return {
      publicKey: existing.public_key,
      privateKey: existing.private_key,
      subject: existing.subject,
    };
  }

  const generated = webpush.generateVAPIDKeys();
  const subject = new URL(supabaseUrl).origin;
  const { error: upsertError } = await supabase
    .from("push_vapid_config")
    .upsert({
      id: true,
      public_key: generated.publicKey,
      private_key: generated.privateKey,
      subject,
      updated_at: new Date().toISOString(),
    });

  if (upsertError) {
    throw upsertError;
  }

  return {
    publicKey: generated.publicKey,
    privateKey: generated.privateKey,
    subject,
  };
}

async function removeSubscription(endpoint: string) {
  const { error } = await supabase
    .from("push_subscriptions")
    .delete()
    .eq("endpoint", endpoint);

  if (error) {
    console.error("Remove invalid push subscription failed", error);
  }
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: corsHeaders,
  });
}
