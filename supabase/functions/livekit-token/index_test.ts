import {
  assertEquals,
  assert,
} from "jsr:@std/assert";
import { handleRequest } from "./index.ts";
import type { Deps, TokenClaims } from "./index.ts";

const FAKE_USER_ID = "11111111-1111-1111-1111-111111111111";

function testDeps(overrides: Partial<Deps> = {}): Deps {
  const sawJwt: TokenClaims[] = [];
  const deps: Deps = {
    getEnv: (k: string): string | undefined => {
      const env: Record<string, string> = {
        LIVEKIT_URL: "wss://test.livekit.cloud",
        LIVEKIT_TOKEN_TTL_MS: "1800000",
      };
      return env[k];
    },
    verifyUser: async (authHeader: string | null) => {
      if (!authHeader?.startsWith("Bearer ")) return null;
      return { id: FAKE_USER_ID, name: "Test User" };
    },
    buildJwt: (claims: TokenClaims): string => {
      sawJwt.push(claims);
      return "FAKE_JWT_TOKEN";
    },
    ...overrides,
  };
  return Object.assign(deps, { sawJwt });
}

function authHeaders(token: string = "valid-token"): Headers {
  return new Headers({ authorization: `Bearer ${token}` });
}

function makeRequest(body: unknown, headers: Headers = authHeaders()): Request {
  return new Request("http://localhost/livekit-token", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

Deno.test("no auth header -> 401", async () => {
  const deps = testDeps();
  const res = await handleRequest(makeRequest({ roomName: "room-1" }, new Headers()), deps);
  assertEquals(res.status, 401);
  assertEquals(await res.json(), { error: "unauthorized" });
});

Deno.test("invalid user -> 401", async () => {
  const deps = testDeps({
    verifyUser: async () => null,
  });
  const res = await handleRequest(makeRequest({ roomName: "room-1" }), deps);
  assertEquals(res.status, 401);
});

Deno.test("viewer request -> 200 with server_url + participant_token, no secrets", async () => {
  const deps = testDeps();
  const res = await handleRequest(
    makeRequest({ roomName: "room-1", isStreamer: false }),
    deps,
  );
  assertEquals(res.status, 200);

  const body = await res.json();
  assert(typeof body.server_url === "string" && body.server_url.length > 0);
  assert(typeof body.participant_token === "string" && body.participant_token.length > 0);

  const raw = JSON.stringify(body).toLowerCase();
  assert(!raw.includes("api_key"));
  assert(!raw.includes("api_secret"));
  assert(!raw.includes("secret"));
  assert(!raw.includes("livekit_api_key"));
  assert(!raw.includes("livekit_api_secret"));
});

Deno.test("viewer jwt payload reflects identity + canPublish=false", async () => {
  const deps = testDeps();
  await handleRequest(makeRequest({ roomName: "room-1", isStreamer: false }), deps);
  const claims = (deps as unknown as { sawJwt: TokenClaims[] }).sawJwt[0];
  assertEquals(claims.identity, FAKE_USER_ID);
  assertEquals(claims.grants.roomJoin, true);
  assertEquals(claims.grants.canPublish, false);
  assertEquals(claims.grants.canSubscribe, true);
  assertEquals(claims.grants.roomCreate, false);
  assertEquals(claims.grants.room, "room-1");
});

Deno.test("streamer request -> token canPublish=true && roomCreate=true", async () => {
  const deps = testDeps();
  await handleRequest(makeRequest({ roomName: "stream-room", isStreamer: true }), deps);
  const claims = (deps as unknown as { sawJwt: TokenClaims[] }).sawJwt[0];
  assertEquals(claims.grants.canPublish, true);
  assertEquals(claims.grants.roomCreate, true);
});

Deno.test("missing roomName -> 400", async () => {
  const deps = testDeps();
  const res = await handleRequest(makeRequest({}), deps);
  assertEquals(res.status, 400);
});

Deno.test("invalid roomName -> 400", async () => {
  const deps = testDeps();
  const res = await handleRequest(makeRequest({ roomName: "bad room name!" }), deps);
  assertEquals(res.status, 400);
});

Deno.test("OPTIONS preflight -> 200", async () => {
  const deps = testDeps();
  const res = await handleRequest(
    new Request("http://localhost/livekit-token", { method: "OPTIONS" }),
    deps,
  );
  assertEquals(res.status, 200);
});
