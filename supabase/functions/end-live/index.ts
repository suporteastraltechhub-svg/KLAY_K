import { createClient } from "npm:@supabase/supabase-js@^2";
import { json, opts } from "../_shared/cors.ts";
import { verifyUser } from "../_shared/auth.ts";
import { createRoomClient } from "../_shared/livekit.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return opts();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const user = await verifyUser(req.headers.get("authorization"));
  if (!user) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const liveId = typeof body.live_id === "string" ? body.live_id.trim() : "";
  if (!liveId) return json({ error: "live_id_required" }, 400);

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );

  const { data: live, error: fetchError } = await serviceClient
    .from("lives")
    .select("id, streamer_id, room_name, status")
    .eq("id", liveId)
    .maybeSingle();

  if (fetchError || !live) {
    return json({ error: "live_not_found" }, 404);
  }

  // Somente o dono da live pode encerrar.
  if (live.streamer_id !== user.id) {
    return json({ error: "forbidden" }, 403);
  }

  if (live.status !== "ended") {
    const { error: updateError } = await serviceClient
      .from("lives")
      .update({ status: "ended", ended_at: new Date().toISOString() })
      .eq("id", liveId);

    if (updateError) {
      console.error("end-live update error:", updateError.message);
      return json({ error: "update_failed", message: updateError.message }, 400);
    }

    const { error: eventError } = await serviceClient
      .from("live_events")
      .insert({
        live_id: liveId,
        event_type: "LIVE_ENDED",
        user_id: user.id,
        username: user.name ?? null,
        metadata: {},
      });
    if (eventError) {
      console.error("end-live event insert error:", eventError.message);
    }
  }

  // Encerra a sala no LiveKit.
  const roomClient = createRoomClient();
  if (roomClient) {
    try {
      await roomClient.deleteRoom(live.room_name);
    } catch (e) {
      console.error(
        "end-live deleteRoom error:",
        e instanceof Error ? e.message : String(e),
      );
    }
  }

  return json({ ok: true });
});