import { createClient } from "npm:@supabase/supabase-js@^2";
import { json, opts } from "../_shared/cors.ts";
import { verifyUser } from "../_shared/auth.ts";
import { createRoomClient } from "../_shared/livekit.ts";

function sanitizeText(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, max);
}

/** Gera um slug único e simples a partir do título (com triagem random). */
function slugify(title: string, suffix: string): string {
  const base = title
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "")
    .slice(0, 48);
  return `${base || "sala"}-${suffix}`;
}

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

  const title = sanitizeText(body.title, 80);
  if (!title) return json({ error: "title_required" }, 400);

  const description = sanitizeText(body.description, 2000);
  const category = sanitizeText(body.category, 50);

  const roomName = `voice-${crypto.randomUUID()}`;
  const shortId = crypto.randomUUID().slice(0, 6);

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );

  const { data, error } = await serviceClient
    .from("audio_rooms")
    .insert({
      title,
      slug: slugify(title, shortId),
      description,
      category,
      room_name: roomName,
      owner_id: user.id,
      participant_count: 1,
      speaker_count: 1,
      status: "live",
      is_public: true,
    })
    .select("id")
    .single();

  if (error || !data) {
    console.error("create-audio-room insert error:", error?.message ?? "no data");
    return json({ error: "insert_failed", message: error?.message ?? "failed" }, 400);
  }

  // Prepara a sala no LiveKit (idempotente/opcional; o token do dono terá
  // roomCreate caso falhe aqui).
  const roomClient = createRoomClient();
  if (roomClient) {
    try {
      await roomClient.createRoom({
        name: roomName,
        metadata: JSON.stringify({ audio_room_id: data.id }),
        emptyTimeout: 120,
      });
    } catch (e) {
      console.error(
        "create-audio-room createRoom (opcional):",
        e instanceof Error ? e.message : String(e),
      );
    }
  }

  return json({ audio_room_id: data.id, room_name: roomName });
});