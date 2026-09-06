import { createClient } from "npm:@supabase/supabase-js@^2";
import { json, opts } from "../_shared/cors.ts";
import { verifyUser } from "../_shared/auth.ts";

/**
 * gift-admin — CRUD administrativo do catálogo de presentes.
 * Apenas usuários com profiles.is_admin = true conseguem escrever.
 * As operações são executadas com o service role (ignora RLS) e cada resposta
 * reflete o estado persistido. Nenhuma operação usa dados mockados.
 */

interface AdminCommands {
  create_gift?: Record<string, unknown>;
  update_gift?: { id: string; patch: Record<string, unknown> };
  set_gift_status?: { id: string; status: string };
  create_category?: Record<string, unknown>;
  update_category?: { id: string; patch: Record<string, unknown> };
  create_rarity?: Record<string, unknown>;
  update_rarity?: { id: string; patch: Record<string, unknown> };
  create_effect?: Record<string, unknown>;
  create_event?: Record<string, unknown>;
  grant_credits?: { user_id: string; amount: number; note?: string };
}

async function ensureAdmin(
  svc: ReturnType<typeof createClient>,
  userId: string,
): Promise<boolean> {
  const { data, error } = await svc
    .from("profiles")
    .select("is_admin")
    .eq("id", userId)
    .maybeSingle();
  return !error && data?.is_admin === true;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return opts();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const user = await verifyUser(req.headers.get("authorization"));
  if (!user) return json({ error: "unauthorized" }, 401);

  const svc = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );

  if (!(await ensureAdmin(svc, user.id))) {
    return json({ error: "forbidden" }, 403);
  }

  let body: AdminCommands;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  // Concede créditos (bônus/admin). Devito é feito apenas via send-gift.
  if (body.grant_credits) {
    const { user_id, amount, note } = body.grant_credits;
    const delta = Math.abs(Math.floor(amount));
    if (!user_id || delta <= 0) return json({ error: "invalid_amount" }, 400);
    const { data: w, error: wErr } = await svc
      .from("user_wallets")
      .select("credits").eq("user_id", user_id).maybeSingle();
    if (wErr) return json({ error: "wallet_error" }, 500);
    const next = (w?.credits ?? 0) + delta;
    await svc.from("user_wallets").upsert({
      user_id,
      credits: next,
    });
    await svc.from("credit_transactions").insert({
      user_id,
      delta,
      balance_after: next,
      kind: "grant",
      ref_type: "admin",
      note: note ?? "Créditos concedidos por administrador",
    });
    return json({ ok: true, balance: next });
  }

  // ---- GIFTS ----
  if (body.create_gift) {
    const g = body.create_gift;
    if (typeof g.id !== "string" || typeof g.name !== "string") {
      return json({ error: "id_and_name_required" }, 400);
    }
    const row = {
      id: g.id,
      name: g.name,
      category_id: String(g.category_id ?? "comuns"),
      rarity_id: String(g.rarity_id ?? "comum"),
      credits: Math.max(0, Math.floor(Number(g.credits ?? 0))),
      icon: String(g.icon ?? "🎁"),
      glyph: String(g.glyph ?? ""),
      animation_key: String(g.animation_key ?? "sparkle"),
      effects: g.effects ?? {},
      description: String(g.description ?? ""),
      status: g.status === "inactive" ? "inactive" : "active",
      sort_order: Math.floor(Number(g.sort_order ?? 0)),
      is_featured: g.is_featured === true,
      is_exclusive: g.is_exclusive === true,
      is_temporary: g.is_temporary === true,
      is_event_gift: g.is_event_gift === true,
      is_limited: g.is_limited === true,
      is_tradable: g.is_tradable === false ? false : true,
      regions: Array.isArray(g.regions) ? g.regions : [],
      event_id: typeof g.event_id === "string" ? g.event_id : null,
    };
    const { data, error } = await svc.from("gifts").insert(row).select().single();
    if (error) return json({ error: "insert_failed", message: error.message }, 400);
    return json({ ok: true, gift: data });
  }

  if (body.update_gift) {
    const { id, patch } = body.update_gift;
    const allowed = [
      "name", "category_id", "rarity_id", "credits", "icon", "glyph",
      "animation_key", "effects", "description", "status", "sort_order",
      "is_featured", "is_exclusive", "is_temporary", "is_event_gift",
      "is_limited", "is_tradable", "regions", "event_id",
      "featured_start", "featured_end",
    ];
    const clean: Record<string, unknown> = {};
    for (const k of allowed) if (k in patch) clean[k] = patch[k];
    clean.updated_at = new Date().toISOString();
    const { data, error } = await svc
      .from("gifts").update(clean).eq("id", id).select().single();
    if (error) return json({ error: "update_failed", message: error.message }, 400);
    return json({ ok: true, gift: data });
  }

  if (body.set_gift_status) {
    const { id, status } = body.set_gift_status;
    const s = status === "inactive" ? "inactive" : "active";
    const { data, error } = await svc
      .from("gifts").update({ status: s }).eq("id", id).select().single();
    if (error) return json({ error: "status_failed", message: error.message }, 400);
    return json({ ok: true, gift: data });
  }

  // ---- CATEGORIES ----
  if (body.create_category) {
    const c = body.create_category;
    const { data, error } = await svc.from("gift_categories").insert({
      id: String(c.id ?? crypto.randomUUID()),
      name: String(c.name ?? ""),
      emoji: String(c.emoji ?? "🎁"),
      "order": Math.floor(Number(c.order ?? 0)),
    }).select().single();
    if (error) return json({ error: "insert_failed", message: error.message }, 400);
    return json({ ok: true, category: data });
  }
  if (body.update_category) {
    const { id, patch } = body.update_category;
    const { data, error } = await svc
      .from("gift_categories").update(patch).eq("id", id).select().single();
    if (error) return json({ error: "update_failed", message: error.message }, 400);
    return json({ ok: true, category: data });
  }

  // ---- RARITIES ----
  if (body.create_rarity) {
    const r = body.create_rarity;
    const { data, error } = await svc.from("gift_rarities").insert({
      id: String(r.id ?? crypto.randomUUID()),
      name: String(r.name ?? ""),
      emoji: String(r.emoji ?? ""),
      "order": Math.floor(Number(r.order ?? 0)),
      color: String(r.color ?? "#FFFFFF"),
    }).select().single();
    if (error) return json({ error: "insert_failed", message: error.message }, 400);
    return json({ ok: true, rarity: data });
  }
  if (body.update_rarity) {
    const { id, patch } = body.update_rarity;
    const { data, error } = await svc
      .from("gift_rarities").update(patch).eq("id", id).select().single();
    if (error) return json({ error: "update_failed", message: error.message }, 400);
    return json({ ok: true, rarity: data });
  }

  // ---- EFFECTS ----
  if (body.create_effect) {
    const e = body.create_effect;
    const { data, error } = await svc.from("gift_effects").insert({
      id: String(e.id ?? crypto.randomUUID()),
      name: String(e.name ?? ""),
      kind: e.kind === "custom" ? "custom" : "preset",
      params: e.params ?? {},
      tier: Math.floor(Number(e.tier ?? 1)),
    }).select().single();
    if (error) return json({ error: "insert_failed", message: error.message }, 400);
    return json({ ok: true, effect: data });
  }

  // ---- EVENTS ----
  if (body.create_event) {
    const ev = body.create_event;
    const { data, error } = await svc.from("gift_events").insert({
      id: String(ev.id ?? crypto.randomUUID()),
      name: String(ev.name ?? ""),
      description: String(ev.description ?? ""),
      starts_at: typeof ev.starts_at === "string" ? ev.starts_at : null,
      ends_at: typeof ev.ends_at === "string" ? ev.ends_at : null,
    }).select().single();
    if (error) return json({ error: "insert_failed", message: error.message }, 400);
    return json({ ok: true, event: data });
  }

  return json({ error: "no_command" }, 400);
});
