import { AccessToken } from "npm:livekit-server-sdk@^2.9.0";
import { createClient } from "npm:@supabase/supabase-js@^2";
import { corsHeaders, json, opts } from "../_shared/cors.ts";
import { type AuthedUser, verifyUser } from "../_shared/auth.ts";

export interface TokenClaims {
  identity: string;
  name?: string;
  ttl: number;
  grants: {
    roomJoin: boolean;
    room: string;
    canPublish: boolean;
    canSubscribe: boolean;
    canPublishData: boolean;
    roomCreate: boolean;
  };
}

export interface RoomOwner {
  ownerId: string | null;
  liveId: string | null;
  active?: boolean;
}

export interface Deps {
  getEnv(k: string): string | undefined;
  verifyUser(authHeader: string | null): Promise<AuthedUser | null>;
  buildJwt(claims: TokenClaims): string | Promise<string>;
  resolveRoomOwner?(
    roomName: string,
    liveId: string | null,
  ): Promise<RoomOwner | null>;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function sanitizeRoomName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.trim();
  if (cleaned.length === 0 || cleaned.length > 64) return null;
  if (!/^[A-Za-z0-9-]+$/.test(cleaned)) return null;
  return cleaned;
}

function sanitizeDisplayName(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const cleaned = value.trim();
  if (cleaned.length === 0) return undefined;
  return cleaned.slice(0, 40);
}

function readLiveId(body: Record<string, unknown>): {
  value: string | null;
  invalid: boolean;
} {
  const raw = body.live_id !== undefined ? body.live_id : body.liveId;
  if (raw === undefined || raw === null) return { value: null, invalid: false };
  if (typeof raw !== "string") return { value: null, invalid: true };
  const value = raw.trim();
  if (value.length === 0) return { value: null, invalid: false };
  if (!UUID_PATTERN.test(value)) return { value: null, invalid: true };
  return { value: value.toLowerCase(), invalid: false };
}

export async function handleRequest(
  req: Request,
  deps: Deps,
): Promise<Response> {
  if (req.method === "OPTIONS") return opts();

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("authorization");
  const user = await deps.verifyUser(authHeader);
  if (!user) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown>;
  try {
    const parsed: unknown = await req.json();
    if (
      typeof parsed !== "object" ||
      parsed === null ||
      Array.isArray(parsed)
    ) {
      return json({ error: "invalid_json" }, 400);
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const roomName = sanitizeRoomName(body.roomName);
  if (roomName === null) return json({ error: "invalid_room_name" }, 400);

  const liveIdResult = readLiveId(body);
  if (liveIdResult.invalid) return json({ error: "invalid_live_id" }, 400);
  const liveId = liveIdResult.value;

  let roomOwner: RoomOwner | null = null;
  if (deps.resolveRoomOwner) {
    try {
      roomOwner = await deps.resolveRoomOwner(roomName, liveId);
    } catch {
      console.error("livekit room ownership lookup failed");
      return json({ error: "room_lookup_failed" }, 503);
    }
  }

  const isStreamer = deps.resolveRoomOwner
    ? roomOwner?.ownerId === user.id
    : body.isStreamer === true;
  const role =
    typeof body.role === "string" ? body.role.trim().slice(0, 32) : "";
  const displayName = sanitizeDisplayName(body.displayName);
  const name = displayName ?? user.name ?? "Participante";

  const defaultTtl = 1800000;
  const ttlRaw = deps.getEnv("LIVEKIT_TOKEN_TTL_MS");
  const ttl = ttlRaw ? Number.parseInt(ttlRaw, 10) : defaultTtl;
  const parsedTtl = Number.isFinite(ttl) && ttl > 0 ? ttl : defaultTtl;

  const canPublishAsHost = isStreamer && (roomOwner?.active ?? true);
  const claims: TokenClaims = {
    identity: user.id,
    name,
    ttl: parsedTtl,
    grants: {
      roomJoin: true,
      room: roomName,
      canPublish:
        canPublishAsHost || (role === "speaker" && roomOwner?.liveId === null),
      canSubscribe: true,
      canPublishData: true,
      roomCreate: canPublishAsHost,
    },
  };

  const participantToken = await deps.buildJwt(claims);
  return json({
    server_url: deps.getEnv("LIVEKIT_URL") ?? "",
    participant_token: participantToken,
  });
}

function buildRealDeps(): Deps {
  const getEnv = (k: string): string | undefined => Deno.env.get(k);
  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );

  const buildJwt = (claims: TokenClaims): Promise<string> => {
    const accessToken = new AccessToken(
      getEnv("LIVEKIT_API_KEY"),
      getEnv("LIVEKIT_API_SECRET"),
      {
        identity: claims.identity,
        name: claims.name,
        ttl: claims.ttl,
      },
    );
    accessToken.addGrant(claims.grants);
    return accessToken.toJwt();
  };

  const resolveRoomOwner = async (
    roomName: string,
    liveId: string | null,
  ): Promise<RoomOwner | null> => {
    let liveQuery = serviceClient
      .from("lives")
      .select("id,streamer_id,status")
      .eq("room_name", roomName);
    if (liveId !== null) liveQuery = liveQuery.eq("id", liveId);

    const { data: liveData, error: liveError } = await liveQuery.maybeSingle();
    if (liveError) throw new Error("live_lookup_failed");
    if (liveData) {
      const live = liveData as {
        id: string;
        streamer_id: string;
        status: string;
      };
      return {
        ownerId: live.streamer_id,
        liveId: live.id,
        active: live.status === "live",
      };
    }
    if (liveId !== null) return null;

    const { data: audioData, error: audioError } = await serviceClient
      .from("audio_rooms")
      .select("id,owner_id")
      .eq("room_name", roomName)
      .maybeSingle();
    if (audioError) throw new Error("audio_room_lookup_failed");
    if (!audioData) return null;
    const audio = audioData as { id: string; owner_id: string | null };
    return { ownerId: audio.owner_id, liveId: null, active: true };
  };

  return { getEnv, verifyUser, buildJwt, resolveRoomOwner };
}

Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }
  return handleRequest(req, buildRealDeps());
});
