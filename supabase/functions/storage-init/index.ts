import { createClient } from "npm:@supabase/supabase-js@^2";
import { json, opts } from "../_shared/cors.ts";

/**
 * Utilitário de setup (uso interno/único): garante a existência dos buckets de
 * Storage do KLAY K com a flag pública correta. Roda com a service role key
 * injetada pelo Supabase (nunca exposta ao aplicativo). Pode ser chamado
 * repetidamente (idempotente) com um JWT válido — útil após um reset ou em CI.
 */

const BUCKETS = [
  { name: "avatars", public: true, mime: ["image/png", "image/jpeg", "image/webp"] },
  { name: "covers", public: true, mime: ["image/png", "image/jpeg", "image/webp"] },
  { name: "videos", public: false, mime: ["video/mp4", "video/webm", "video/quicktime"] },
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return opts();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("authorization");
  const admin = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );
  const { data: user } = await admin.auth.getUser(authHeader?.split(" ")[1] ?? "");
  if (!user?.user) return json({ error: "unauthorized" }, 401);

  const results: Record<string, string> = {};
  for (const b of BUCKETS) {
    const { data: existing } = await admin.storage.getBucket(b.name);
    if (!existing) {
      const { error: createErr } = await admin.storage.createBucket(b.name, {
        public: b.public,
        fileSizeLimit: b.name === "videos" ? 209715200 : 10485760,
        allowedMimeTypes: b.mime,
      });
      results[b.name] = createErr ? `create_failed: ${createErr.message}` : "created";
      continue;
    }
    if (existing.public !== b.public) {
      const { error: updErr } = await admin.storage.updateBucket(b.name, {
        public: b.public,
        allowedMimeTypes: b.mime,
      });
      results[b.name] = updErr ? `update_failed: ${updErr.message}` : "updated";
    } else {
      results[b.name] = "ok";
    }
  }

  return json({ ok: true, buckets: results });
});
