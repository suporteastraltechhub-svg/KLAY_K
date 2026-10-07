import { WebhookReceiver } from "npm:livekit-server-sdk@^2.9.0";
import { createClient } from "npm:@supabase/supabase-js@^2";
import { corsHeaders, json } from "../_shared/cors.ts";

function buildReceiver(): WebhookReceiver {
  return new WebhookReceiver(
    Deno.env.get("LIVEKIT_API_KEY") ?? "",
    Deno.env.get("LIVEKIT_API_SECRET") ?? "",
  );
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
  const authHeader = req.headers.get("authorization") ?? "";

  // O LiveKit Cloud assina o request com um JWT no header Authorization
  // (HS256, claim "sha256" = hash do corpo em base64). Sem a validação
  // correta qualquer webhook legítimo era rejeitado (401) e as lives
  // encerradas nunca viravam LIVE_ENDED no banco ("lives fantasmas").
  let webhookEvent;
  try {
    webhookEvent = await buildReceiver().receive(rawBody, authHeader);
  } catch (e) {
    console.error(
      "livekit-webhook: signature verification failed:",
      e instanceof Error ? e.message : String(e),
    );
    return json({ error: "invalid_signature" }, 401);
  }

  // Respond quickly in all cases; secondary processing must not fail the request.
  const respond200 = () => json({ ok: true });

  try {
    const eventType = mapEvent(webhookEvent.event);
    if (!eventType) return respond200();

    const roomName = webhookEvent.room?.name;
    if (!roomName) return respond200();

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL") as string,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
    );

    const { data: live } = await serviceClient
      .from("lives")
      .select("id, status, streamer_id")
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

    const identity = webhookEvent.participant?.identity ?? "";
    if (identity.startsWith("bot") || identity.startsWith("klayk")) {
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

    if (
      userId !== null &&
      (eventType === "USER_JOINED" || eventType === "USER_LEFT")
    ) {
      let presenceError: { message: string } | null = null;
      if (eventType === "USER_JOINED") {
        const result = await serviceClient.from("live_participants").upsert(
          {
            live_id: live.id,
            user_id: userId,
            is_streamer: userId === live.streamer_id,
            joined_at: new Date().toISOString(),
            left_at: null,
          },
          { onConflict: "live_id,user_id" },
        );
        presenceError = result.error;
      } else {
        const result = await serviceClient
          .from("live_participants")
          .update({ left_at: new Date().toISOString() })
          .eq("live_id", live.id)
          .eq("user_id", userId);
        presenceError = result.error;
      }
      if (presenceError) {
        console.error(
          "livekit-webhook: presence update error:",
          presenceError.message,
        );
      }
    }

    const { error } = await serviceClient.from("live_events").insert({
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
