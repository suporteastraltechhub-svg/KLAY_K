import { createClient } from "npm:@supabase/supabase-js@^2";
import { json, opts } from "../_shared/cors.ts";

/**
 * Gera uma URL assinada de curta duração para ler um objeto do Storage.
 * Necessário para vídeos no bucket privado `videos`. Usa a service role key
 * injetada pelo servidor — o app nunca recebe a service role.
 */

function sanitizePath(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.trim().replace(/^\/+/, "");
  if (cleaned.length === 0 || cleaned.length > 500) return null;
  if (cleaned.includes("..")) return null;
  return cleaned;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return opts();

  const client = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );
  const token = req.headers.get("authorization")?.split(" ")[1] ?? "";
  const { data } = await client.auth.getUser(token);
  if (!data?.user) return json({ error: "unauthorized" }, 401);

  // Aceita o path tanto via query string (GET) quanto via JSON body (POST),
  // para compatibilidade com o SupabaseService.invoke do Flutter.
  let bucket = "videos";
  let rawPath: unknown = null;
  if (req.method === "POST") {
    try {
      const body = await req.json();
      bucket = typeof body?.bucket === "string" ? body.bucket : bucket;
      rawPath = body?.path ?? null;
    } catch {
      return json({ error: "bad_body" }, 400);
    }
  } else {
    const url = new URL(req.url);
    bucket = url.searchParams.get("bucket") ?? bucket;
    rawPath = url.searchParams.get("path");
  }
  const path = sanitizePath(rawPath);
  if (!path) return json({ error: "path_required" }, 400);

  const { data: signed, error } = await client.storage
    .from(bucket)
    .createSignedUrl(path, 3600);
  if (error || !signed) {
    return json({ error: "signed_url_failed", message: error?.message }, 400);
  }

  return json({ url: signed.signedUrl, expires_in: 3600 });
});
