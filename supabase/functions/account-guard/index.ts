import { createClient } from "npm:@supabase/supabase-js@^2";
import { json, opts } from "../_shared/cors.ts";
import { verifyUser } from "../_shared/auth.ts";

/**
 * ACCOUNT GUARD — ações de segurança da própria conta via auth admin real:
 *  - change_password: re-autentica com a senha atual (sem falso-positivo),
 *    aplica a nova senha via admin API e revoga as demais sessões.
 * Nunca usa "auth de mentira": tudo passa pelo GoTrue/admin real do Supabase.
 */
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

  const action = typeof body.action === "string" ? body.action : "";
  if (action !== "change_password") {
    return json({ error: "bad_action" }, 400);
  }

  const currentPassword = typeof body.current_password === "string"
    ? body.current_password
    : "";
  const newPassword = typeof body.new_password === "string"
    ? body.new_password
    : "";
  if (!currentPassword) {
    return json({ error: "current_password_required" }, 400);
  }
  if (newPassword.length < 8) {
    return json({ error: "password_too_short" }, 400);
  }
  if (newPassword === currentPassword) {
    return json({ error: "same_password" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL") as string;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") as string;
  const svc = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string);

  // Passo 1: re-autentica com a senha ATUAL (vingorosa e honesta).
  const { data: me, error: meErr } = await svc.auth.admin.getUserById(user.id);
  if (meErr || !me?.user?.email) {
    return json({ error: "account_lookup_failed" }, 400);
  }
  const check = await createClient(url, anonKey).auth.signInWithPassword({
    email: me.user.email,
    password: currentPassword,
  });
  if (check.error) {
    return json({ error: "wrong_password" }, 400);
  }

  // Passo 2: troca de senha real via auth admin.
  const { error: upErr } = await svc.auth.admin.updateUserById(user.id, {
    password: newPassword,
  });
  if (upErr) {
    return json({ error: "update_failed", message: upErr.message }, 400);
  }

  // Passo 3: revoga as outras sessões mantendo a atual (via refresh token do
  // cliente chamando o RPC security definer com o próprio JWT do usuário).
  const refreshToken = typeof body.refresh_token === "string" &&
      body.refresh_token.length > 0
    ? body.refresh_token
    : "";
  if (refreshToken) {
    const authHeader = req.headers.get("authorization") ?? "";
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { error: revErr } = await caller.rpc("auth_revoke_other_sessions", {
      p_refresh_token: refreshToken,
    });
    if (revErr) {
      console.error("revoke_other_sessions:", revErr.message);
    }
  }

  return json({ ok: true });
});