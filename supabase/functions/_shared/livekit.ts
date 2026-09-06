import { RoomServiceClient } from "npm:livekit-server-sdk@^2.9.0";

/**
 * Cria o client administrativo do LiveKit. Requer as Secrets
 * LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET — nunca hardcoded e
 * nunca expostos ao aplicativo Flutter.
 */
export function createRoomClient(): RoomServiceClient | null {
  const url = Deno.env.get("LIVEKIT_URL");
  const apiKey = Deno.env.get("LIVEKIT_API_KEY");
  const apiSecret = Deno.env.get("LIVEKIT_API_SECRET");
  if (!url || !apiKey || !apiSecret) return null;
  return new RoomServiceClient(url, apiKey, apiSecret);
}