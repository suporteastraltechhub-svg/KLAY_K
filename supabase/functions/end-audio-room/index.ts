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

  const audioRoomId = typeof body.audio_room_id === "string"
    ? body.audio_room_id.trim()
    : "";
  if (!audioRoomId) return json({ error: "audio_room_id_required" }, 400);

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );

  const { data: room, error: fetchError } = await serviceClient
    .from("audio_rooms")
    .select("id, owner_id, room_name, status")
    .eq("id", audioRoomId)
    .maybeSingle();

  if (fetchError || !room) {
    return json({ error: "audio_room_not_found" }, 404);
  }

  // Somente o dono da sala pode encerrar.
  if (room.owner_id !== user.id) {
    return json({ error: "forbidden" }, 403);
  }

  if (room.status !== "ended") {
    const { error: updateError } = await serviceClient
      .from("audio_rooms")
      .update({ status: "ended", ended_at: new Date().toISOString() })
      .eq("id", audioRoomId);

    if (updateError) {
      console.error("end-audio-room update error:", updateError.message);
      return json({ error: "update_failed", message: updateError.message }, 400);
    }
  }

  // Encerra a sala no LiveKit.
  const roomClient = createRoomClient();
  if (roomClient) {
    try {
      await roomClient.deleteRoom(room.room_name);
    } catch (e) {
      console.error(
        "end-audio-room deleteRoom error:",
        e instanceof Error ? e.message : String(e),
      );
    }
  }

  return json({ ok: true });
});