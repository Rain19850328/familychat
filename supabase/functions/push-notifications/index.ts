import { createClient } from "npm:@supabase/supabase-js@2";
import {
  ApplicationServer,
  PushMessageError,
  Urgency,
  exportApplicationServerKey,
  exportVapidKeys,
  generateVapidKeys,
  importVapidKeys,
} from "jsr:@negrel/webpush@0.5.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Content-Type": "application/json",
};

Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") {
      return new Response("ok", {
        headers: corsHeaders,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Supabase environment is not configured." }, 500);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    const vapidConfig = await ensureVapidConfig(supabase, supabaseUrl);

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

    const applicationServer = await ApplicationServer.new({
      contactInformation: vapidConfig.subject,
      vapidKeys: vapidConfig.vapidKeys,
    });

    let sent = 0;
    let removed = 0;
    let failed = 0;

    for (const delivery of batch) {
      try {
        const subscriber = applicationServer.subscribe(delivery.subscription);
        await subscriber.pushTextMessage(JSON.stringify({
          title: delivery.title,
          body: delivery.body,
          tag: delivery.tag,
          data: delivery.data,
        }), {
          urgency: Urgency.High,
          topic: delivery.tag,
          ttl: 60,
        });
        sent += 1;
      } catch (error) {
        if (error instanceof PushMessageError && error.isGone()) {
          await removeSubscription(supabase, delivery.endpoint);
          removed += 1;
          continue;
        }

        failed += 1;
        console.error("Web push send failed", {
          endpoint: delivery.endpoint,
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
  } catch (error) {
    console.error("Push notifications function failed", error);
    return jsonResponse({
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});

async function ensureVapidConfig(supabase: ReturnType<typeof createClient>, supabaseUrl: string) {
  const { data: existing, error } = await supabase
    .from("push_vapid_config")
    .select("public_key, private_key, subject")
    .eq("id", true)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (existing?.public_key && existing?.private_key && existing?.subject) {
    const vapidKeys = await importVapidKeys({
      publicKey: existing.public_key,
      privateKey: existing.private_key,
    });

    return {
      publicKey: await exportApplicationServerKey(vapidKeys),
      subject: existing.subject,
      vapidKeys,
    };
  }

  const vapidKeys = await generateVapidKeys();
  const exported = await exportVapidKeys(vapidKeys);
  const subject = new URL(supabaseUrl).origin;
  const { error: upsertError } = await supabase
    .from("push_vapid_config")
    .upsert({
      id: true,
      public_key: exported.publicKey,
      private_key: exported.privateKey,
      subject,
      updated_at: new Date().toISOString(),
    });

  if (upsertError) {
    throw upsertError;
  }

  return {
    publicKey: await exportApplicationServerKey(vapidKeys),
    subject,
    vapidKeys,
  };
}

async function removeSubscription(supabase: ReturnType<typeof createClient>, endpoint: string) {
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
