import { createClient } from "npm:@supabase/supabase-js@^2";
import { json, opts } from "../_shared/cors.ts";
import { verifyUser } from "../_shared/auth.ts";
import { createRoomClient } from "../_shared/livekit.ts";

function sanitizeText(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, max);
}

function sanitizeHashtags(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const out: string[] = [];
  for (const item of value.slice(0, 10)) {
    const tag = sanitizeText(item, 30);
    if (tag.length > 0) out.push(tag.replace(/^#/, ""));
  }
  return out;
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
  const hashtags = sanitizeHashtags(body.hashtags);
  const privacy = body.privacy === "private" ? "private" : "public";
  const gameName = sanitizeText(body.game_name, 60);
  const coverUrl = sanitizeText(body.cover_url, 500);
  const ageRestricted = body.age_restricted === true;

  const roomName = `live-${crypto.randomUUID()}`;

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );

  const { data, error } = await serviceClient
    .from("lives")
    .insert({
      streamer_id: user.id,
      room_name: roomName,
      title,
      description,
      category,
      hashtags,
      privacy,
      status: "live",
      started_at: new Date().toISOString(),
      viewer_count: 0,
      game_name: gameName || null,
      cover_url: coverUrl || null,
      age_restricted: ageRestricted,
    })
    .select("id")
    .single();

  if (error || !data) {
    console.error("create-live insert error:", error?.message ?? "no data");
    return json({ error: "insert_failed", message: error?.message ?? "failed" }, 400);
  }

  // Prepara a sala no LiveKit. É idempotente e opcional: se falhar (ex.: sem
  // credenciais configuradas), o token do streamer ganha `roomCreate` e a sala
  // é criada no primeiro join do mesmo jeito.
  const roomClient = createRoomClient();
  if (roomClient) {
    try {
      await roomClient.createRoom({
        name: roomName,
        metadata: JSON.stringify({ live_id: data.id }),
        emptyTimeout: 120,
      });
    } catch (e) {
      console.error(
        "create-live createRoom (opcional):",
        e instanceof Error ? e.message : String(e),
      );
    }
  }

  const { error: eventError } = await serviceClient
    .from("live_events")
    .insert({
      live_id: data.id,
      event_type: "LIVE_STARTED",
      user_id: user.id,
      username: user.name ?? null,
      metadata: {},
    });

  if (eventError) {
    console.error("create-live event insert error:", eventError.message);
  }

  return json({ live_id: data.id, room_name: roomName });
});