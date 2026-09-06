import { AccessToken } from "npm:livekit-server-sdk@^2.9.0";
import { corsHeaders, json, opts } from "../_shared/cors.ts";
import { verifyUser, type AuthedUser } from "../_shared/auth.ts";

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

export interface Deps {
  getEnv(k: string): string | undefined;
  verifyUser(authHeader: string | null): Promise<AuthedUser | null>;
  buildJwt(claims: TokenClaims): string | Promise<string>;
}

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

export async function handleRequest(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") {
    return opts();
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("authorization");
  const user = await deps.verifyUser(authHeader);
  if (!user) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const roomName = sanitizeRoomName(body.roomName);
  if (roomName === null) {
    return json({ error: "invalid_room_name" }, 400);
  }

  const isStreamer = body.isStreamer === true;
  const displayName = sanitizeDisplayName(body.displayName);

  const name = displayName ??
    user.name ??
    "Participante";

  const defaultTtl = 1800000;
  const ttlRaw = deps.getEnv("LIVEKIT_TOKEN_TTL_MS");
  const ttl = ttlRaw ? Number.parseInt(ttlRaw, 10) : defaultTtl;
  const parsedTtl = Number.isFinite(ttl) && ttl > 0 ? ttl : defaultTtl;

  // Role opcional para salas de voz (Áudio). Default preserva o comportamento
  // atual baseado em `isStreamer` — lives existentes não são afetadas.
  //   streamer : pode publicar E criar a sala (padrão dos streamers de live)
  //   speaker  : pode publicar áudio, mas NÃO cria a sala (participante de voz)
  //   listener : apenas ouve (canPublish = false)
  const role = typeof body.role === "string" ? body.role : undefined;
  const canPublish = role === "speaker" || (role === undefined && isStreamer);
  const canCreateRoom =
    role === undefined ? isStreamer : role === "streamer";

  const claims: TokenClaims = {
    identity: user.id,
    name,
    ttl: parsedTtl,
    grants: {
      roomJoin: true,
      room: roomName,
      // O streamer pode criar a sala (aperta o gatilho de criação no LiveKit
      // caso ela ainda não exista) e publicar vídeo/áudio/dados. Espectadores
      // apenas assistem, mas podem enviar datagrams (reações). Em salas de
      // voz, "speaker" publica áudio mas não cria a sala; "listener" só ouve.
      canPublish,
      canSubscribe: true,
      canPublishData: true,
      roomCreate: canCreateRoom,
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

  const buildJwt = async (claims: TokenClaims): Promise<string> => {
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

  return { getEnv, verifyUser, buildJwt };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }
  return handleRequest(req, buildRealDeps());
});
