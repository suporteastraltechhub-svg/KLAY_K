import { createClient } from "npm:@supabase/supabase-js@^2";
import { corsHeaders, json } from "../_shared/cors.ts";

async function verifySignature(rawBody: string, signature: string | null): Promise<boolean> {
  if (!signature) return false;
  const secret = Deno.env.get("LIVEKIT_API_SECRET");
  if (!secret) return false;

  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(rawBody));
  const expected = btoa(String.fromCharCode(...new Uint8Array(sig)));
  return expected === signature;
}

function isUuid(value: unknown): boolean {
  return (
    typeof value === "string" &&
    /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(
      value,
    )
  );
}

function mapEvent(event: string): string | null {
  switch (event) {
    case "room_started":
      return "LIVE_STARTED";
    case "room_finished":
      return "LIVE_ENDED";
    case "participant_joined":
      return "USER_JOINED";
    case "participant_left":
      return "USER_LEFT";
    default:
      return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    // O LiveKit chama isto como servidor-a-servidor; CORS cobre preflight
    // quando o endpoint é exercitado a partir do painel/ferramentas.
    return new Response("ok", { status: 200, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const rawBody = await req.text();
  const signature = req.headers.get("x-livekit-signature");
  const valid = await verifySignature(rawBody, signature);
  if (!valid) {
    return json({ error: "invalid_signature" }, 401);
  }

  // Respond quickly in all cases; secondary processing must not fail the request.
  const respond200 = () => json({ ok: true });

  try {
    const payload = JSON.parse(rawBody) as {
      event?: string;
      room?: { name?: string; sid?: string };
      participant?: { identity?: string };
      participantKind?: string;
    };

    const eventType = mapEvent(payload.event ?? "");
    if (!eventType) return respond200();

    const roomName = payload.room?.name;
    if (!roomName) return respond200();

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL") as string,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
    );

    const { data: live } = await serviceClient
      .from("lives")
      .select("id, status")
      .eq("room_name", roomName)
      .maybeSingle();

    if (!live) {
      console.error("livekit-webhook: no live found for room", roomName);
      return respond200();
    }

    // Mantém o estado da live coerente com a sala real do LiveKit.
    if (eventType === "LIVE_STARTED" && live.status === "scheduled") {
      await serviceClient
        .from("lives")
        .update({ status: "live", started_at: new Date().toISOString() })
        .eq("id", live.id);
    } else if (eventType === "LIVE_ENDED" && live.status !== "ended") {
      await serviceClient
        .from("lives")
        .update({ status: "ended", ended_at: new Date().toISOString() })
        .eq("id", live.id);
    }

    const identity = payload.participant?.identity ?? "";
    if (
      identity.startsWith("bot") ||
      identity.startsWith("klayk")
    ) {
      return respond200();
    }

    let userId: string | null = null;
    let username: string | null = null;

    if (isUuid(identity)) {
      userId = identity.toLowerCase();
      const { data: profile } = await serviceClient
        .from("profiles")
        .select("username, display_name")
        .eq("id", userId)
        .maybeSingle();
      if (profile) {
        username = profile.display_name ?? profile.username ?? null;
      }
    }

    const { error } = await serviceClient
      .from("live_events")
      .insert({
        live_id: live.id,
        event_type: eventType,
        user_id: userId,
        username,
        metadata: {},
      });

    if (error) {
      console.error("livekit-webhook: event insert error:", error.message);
    }
  } catch (e) {
    console.error(
      "livekit-webhook: processing error:",
      e instanceof Error ? e.message : String(e),
    );
  }

  return respond200();
});
