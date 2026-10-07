import { createClient } from "npm:@supabase/supabase-js@^2";
import { json, opts } from "../_shared/cors.ts";
import { verifyUser } from "../_shared/auth.ts";

/**
 * DELETE ACCOUNT — exclusão real da própria conta, com duas provas:
 *
 *  1. `confirm_text` precisa ser IGUAL ao e-mail da conta (prova de
 *     intenção explícita, evita clique acidental);
 *  2. `current_password` é reautenticada pelo GoTrue real (prova de que
 *     quem apaga é o dono da sessão, não um token vazado).
 *
 * Só depois das duas confirmações a conta é removida via admin API. Todas
 * as tabelas com `on delete cascade` do usuário caem juntas (perfil, posts,
 * live_participants, blocked_users, settings, tickets, sinalizações etc.),
 * como manda o modelo relacional já existente — nada é inventado aqui.
 *
 * A auditoria é gravada ANTES da remoção, e `audit_logs.actor_id` usa
 * `on delete set null`, então o registro de "conta excluída" sobrevive sem
 * identificar ninguém.
 *
 * Não há como apagar a conta de outra pessoa: o `user.id` vem do JWT
 * verificado, nunca do corpo da requisição.
 */
const DELETION_GRACE_NOTE =
  "A exclusão é definitiva. Perfil, posts, mensagens, presentes, curtidas e configurações vinculados a esta conta serão removidos.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return opts();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const user = await verifyUser(req.headers.get("authorization"));
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

  const action = typeof body.action === "string" ? body.action : "";
  if (action !== "delete_account") return json({ error: "bad_action" }, 400);

  const currentPassword =
    typeof body.current_password === "string" ? body.current_password : "";
  const confirmText =
    typeof body.confirm_text === "string" ? body.confirm_text.trim() : "";
  const reason =
    typeof body.reason === "string" ? body.reason.trim().slice(0, 280) : "";

  if (!currentPassword) {
    return json({ error: "current_password_required" }, 400);
  }
  if (!confirmText) {
    return json(
      {
        error: "confirm_required",
        note: DELETION_GRACE_NOTE,
      },
      400,
    );
  }

  const url = Deno.env.get("SUPABASE_URL") as string;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") as string;
  const svc = createClient(
    url,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );

  const { data: me, error: meErr } = await svc.auth.admin.getUserById(user.id);
  if (meErr || !me?.user?.email) {
    return json({ error: "account_lookup_failed" }, 400);
  }

  if (confirmText.toLowerCase() !== me.user.email.toLowerCase()) {
    return json(
      {
        error: "confirm_mismatch",
        note: `Digite exatamente o e-mail da conta (${me.user.email}) para confirmar.`,
      },
      400,
    );
  }

  const check = await createClient(url, anonKey).auth.signInWithPassword({
    email: me.user.email,
    password: currentPassword,
  });
  if (check.error) {
    return json({ error: "wrong_password" }, 400);
  }

  // Auditoria ANTES da remoção: sobrevive porque actor_id é set null.
  await svc.from("audit_logs").insert({
    actor_id: user.id,
    action: "account.delete_requested",
    entity_type: "user",
    entity_id: user.id,
    details: {
      reason,
      confirmed_by_email: true,
      reauthenticated: true,
      grace_note: DELETION_GRACE_NOTE,
    },
  });

  const { error: delErr } = await svc.auth.admin.deleteUser(user.id);
  if (delErr) {
    await svc.from("audit_logs").insert({
      actor_id: null,
      action: "account.delete_failed",
      entity_type: "user",
      entity_id: user.id,
      details: { reason },
    });
    return json({ error: "delete_failed" }, 500);
  }

  await svc.from("audit_logs").insert({
    actor_id: null,
    action: "account.deleted",
    entity_type: "user",
    entity_id: user.id,
    details: { reason, cascade: "auth.users fks on delete cascade" },
  });

  return json({ ok: true, deleted: true });
});
