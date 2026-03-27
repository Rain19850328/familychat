import { createClient } from "npm:@supabase/supabase-js@2";
import agoraToken from "npm:agora-token@2.0.5";

const { RtcRole, RtcTokenBuilder } = agoraToken as {
  RtcRole: { PUBLISHER: number };
  RtcTokenBuilder: {
    buildTokenWithUid: (
      appId: string,
      appCertificate: string,
      channelName: string,
      uid: number,
      role: number,
      privilegeExpiredTs: number,
    ) => string;
  };
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") {
      return jsonResponse({ ok: true });
    }

    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed." }, 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const agoraAppId = Deno.env.get("AGORA_APP_ID") ?? "";
    const agoraAppCertificate = Deno.env.get("AGORA_APP_CERTIFICATE") ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Supabase environment is not configured." }, 500);
    }

    if (!agoraAppId || !agoraAppCertificate) {
      return jsonResponse({ error: "Agora environment is not configured." }, 500);
    }

    const payload = await request.json().catch(() => null);
    const familyId = normalizeText(payload?.familyId);
    const roomId = normalizeText(payload?.roomId);
    const memberId = normalizeText(payload?.memberId);
    const channelName = normalizeChannelName(payload?.channelName);
    const requestedUid = normalizeUid(payload?.uid);
    const ttlSeconds = normalizeTtl(payload?.ttlSeconds);

    if (!familyId || !roomId || !memberId || !channelName) {
      return jsonResponse({ error: "familyId, roomId, memberId, and channelName are required." }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    const { data: roomMember, error: roomMemberError } = await supabase
      .from("room_members")
      .select("room_id, member_id, family_id")
      .eq("room_id", roomId)
      .eq("member_id", memberId)
      .eq("family_id", familyId)
      .maybeSingle();

    if (roomMemberError) {
      console.error("Room membership check failed", roomMemberError);
      return jsonResponse({ error: "Failed to verify room membership." }, 500);
    }

    if (!roomMember) {
      return jsonResponse({ error: "Member is not allowed in this room." }, 403);
    }

    const nowSeconds = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = nowSeconds + ttlSeconds;
    const uid = requestedUid ?? generateUid();
    const token = RtcTokenBuilder.buildTokenWithUid(
      agoraAppId,
      agoraAppCertificate,
      channelName,
      uid,
      RtcRole.PUBLISHER,
      privilegeExpiredTs,
    );

    return jsonResponse({
      appId: agoraAppId,
      token,
      uid,
      channelName,
      expiresAt: new Date(privilegeExpiredTs * 1000).toISOString(),
      ttlSeconds,
    });
  } catch (error) {
    console.error("Agora token function failed", error);
    return jsonResponse({ error: serializeError(error) }, 500);
  }
});

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: corsHeaders,
  });
}

function normalizeText(value: unknown) {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : "";
}

function normalizeChannelName(value: unknown) {
  const channel = normalizeText(value);
  if (!channel) {
    return "";
  }
  return channel.replace(/[^a-zA-Z0-9_\-]/g, "-").slice(0, 64);
}

function normalizeUid(value: unknown) {
  if (typeof value === "number" && Number.isInteger(value) && value > 0) {
    return value;
  }
  if (typeof value === "string" && /^[1-9][0-9]{0,9}$/.test(value.trim())) {
    return Number(value.trim());
  }
  return null;
}

function normalizeTtl(value: unknown) {
  const raw = typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number(value)
    : NaN;
  if (!Number.isFinite(raw)) {
    return 60 * 60;
  }
  return Math.max(60, Math.min(Math.floor(raw), 60 * 60 * 6));
}

function generateUid() {
  const buffer = new Uint32Array(1);
  crypto.getRandomValues(buffer);
  const value = buffer[0] % 2147480000;
  return Math.max(1, value);
}

function serializeError(error: unknown) {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      stack: error.stack,
    };
  }

  try {
    return JSON.parse(JSON.stringify(error));
  } catch {
    return String(error);
  }
}
