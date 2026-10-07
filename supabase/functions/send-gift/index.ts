import { createClient } from "npm:@supabase/supabase-js@^2";
import { json, opts } from "../_shared/cors.ts";
import { verifyUser } from "../_shared/auth.ts";

interface RichGift {
  id: string;
  name: string;
  credits: number;
  status: string;
  icon: string;
  animation_key: string;
  rarity_id: string;
  is_tradable: boolean;
  is_limited: boolean;
  event_id: string | null;
  featured_start: string | null;
  featured_end: string | null;
}

interface LiveRow {
  id: string;
  streamer_id: string;
  status: string;
}

interface ExistingGift {
  id: string;
  gift_id: string;
  gift_name: string;
  receiver_id: string | null;
  amount: number | string;
  credits_total: number | string;
  balance_after: number | string;
}

interface SpendResult {
  ok?: unknown;
  duplicate?: unknown;
  transaction_id?: unknown;
  amount?: unknown;
  credits_spent?: unknown;
  balance?: unknown;
  unlimited?: unknown;
  earnings_processed?: unknown;
}

interface ServiceQuery {
  select(columns: string): ServiceQuery;
  eq(column: string, value: string): ServiceQuery;
  maybeSingle(): Promise<{ data: unknown; error: unknown }>;
}

interface ServiceClientShape {
  from(table: string): ServiceQuery;
  rpc(
    name: string,
    params?: Record<string, unknown>,
  ): Promise<{ data: unknown; error: unknown }>;
}

const MAX_AMOUNT = 999;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function giftAvailable(g: RichGift, now: number): boolean {
  if (g.status !== "active") return false;
  if (g.featured_start && new Date(g.featured_start).getTime() > now) {
    return false;
  }
  if (g.featured_end && new Date(g.featured_end).getTime() < now) return false;
  return true;
}

function isUuid(value: string): boolean {
  return UUID_PATTERN.test(value);
}

function optionalUuid(
  body: Record<string, unknown>,
  key: string,
): { value: string | null; invalid: boolean } {
  const raw = body[key];
  if (raw === undefined || raw === null) return { value: null, invalid: false };
  if (typeof raw !== "string") return { value: null, invalid: true };
  const value = raw.trim();
  if (value.length === 0) return { value: null, invalid: false };
  return { value: value.toLowerCase(), invalid: !isUuid(value) };
}

function finiteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

async function findExistingGift(
  svc: unknown,
  senderId: string,
  requestId: string,
): Promise<ExistingGift | null> {
  const client = svc as ServiceClientShape;
  const { data, error } = await client
    .from("gift_transactions")
    .select(
      "id,gift_id,gift_name,receiver_id,amount,credits_total,balance_after",
    )
    .eq("request_id", requestId)
    .eq("user_id", senderId)
    .maybeSingle();

  if (error) {
    console.error("gift duplicate lookup failed");
    return null;
  }
  return (data as ExistingGift | null) ?? null;
}

function duplicateResponse(
  g: RichGift,
  existing: ExistingGift,
): Record<string, unknown> {
  return {
    ok: true,
    duplicate: true,
    transaction_id: existing.id,
    gift: {
      id: existing.gift_id,
      name: existing.gift_name,
      icon: g.icon,
      animation_key: g.animation_key,
    },
    amount: finiteNumber(existing.amount) ?? 1,
    credits_spent: finiteNumber(existing.credits_total) ?? 0,
    balance: finiteNumber(existing.balance_after) ?? 0,
    unlimited: false,
  };
}

async function earningsSucceeded(
  svc: unknown,
  transactionId: string,
  receiverId: string,
  grossCredits: number,
): Promise<boolean> {
  try {
    const client = svc as ServiceClientShape;
    const result = await client.rpc("process_gift_earnings", {
      p_gift_tx_id: transactionId,
      p_receiver_id: receiverId,
      p_gross_credits: grossCredits,
    });
    const data = result.data as { ok?: unknown } | null;
    return result.error === null && data?.ok === true;
  } catch {
    return false;
  }
}

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

  const giftId = typeof body.gift_id === "string" ? body.gift_id.trim() : "";
  if (!giftId) return json({ error: "gift_required" }, 400);

  let amount = 1;
  if (body.amount !== undefined && body.amount !== null) {
    if (typeof body.amount !== "number" || !Number.isFinite(body.amount)) {
      return json({ error: "amount_invalid" }, 400);
    }
    amount = Math.floor(body.amount);
    if (amount < 1 || amount > MAX_AMOUNT) {
      return json({ error: "amount_invalid" }, 400);
    }
  }

  const liveField = body.live_id !== undefined ? body.live_id : body.liveId;
  const liveParsed = optionalUuid({ live_id: liveField }, "live_id");
  if (liveParsed.invalid) return json({ error: "invalid_live_id" }, 400);
  const liveId = liveParsed.value;

  const receiverParsed = optionalUuid(body, "receiver_id");
  if (receiverParsed.invalid) {
    return json({ error: "invalid_receiver_id" }, 400);
  }
  const receiverId = receiverParsed.value;

  if (liveId !== null && receiverId === null) {
    return json({ error: "receiver_id_required" }, 400);
  }
  if (receiverId !== null && receiverId === user.id) {
    return json({ error: "cannot_send_to_self" }, 400);
  }

  let requestId: string | null = null;
  if (body.request_id !== undefined && body.request_id !== null) {
    if (typeof body.request_id !== "string") {
      return json({ error: "invalid_request_id" }, 400);
    }
    requestId = body.request_id.trim();
    if (requestId.length < 8 || requestId.length > 64) {
      return json({ error: "invalid_request_id" }, 400);
    }
  }

  const svc = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );

  const { data: gift, error: giftErr } = await svc
    .from("gifts")
    .select(
      "id,name,credits,status,icon,animation_key,rarity_id,is_tradable,is_limited,event_id,featured_start,featured_end",
    )
    .eq("id", giftId)
    .maybeSingle();

  if (giftErr || !gift) {
    return json({ error: "gift_not_found" }, 404);
  }
  const g = gift as RichGift;

  if (!giftAvailable(g, Date.now())) {
    return json({ error: "gift_unavailable" }, 400);
  }

  const hasExisting =
    requestId !== null &&
    (await findExistingGift(svc, user.id, requestId)) !== null;

  if (liveId !== null && !hasExisting) {
    const { data: liveData, error: liveError } = await svc
      .from("lives")
      .select("id,streamer_id,status")
      .eq("id", liveId)
      .maybeSingle();

    if (liveError) {
      console.error("live lookup failed");
      return json({ error: "live_lookup_failed" }, 500);
    }

    const live = liveData as LiveRow | null;
    if (!live) return json({ error: "live_not_found" }, 400);
    if (live.status !== "live") return json({ error: "live_not_active" }, 400);
    if (receiverId === null || live.streamer_id !== receiverId) {
      return json({ error: "receiver_not_streamer" }, 403);
    }
  }

  const { data: founderProfile, error: founderError } = await svc
    .from("profiles")
    .select("founder_unlimited_currency")
    .eq("id", user.id)
    .maybeSingle();

  if (founderError) {
    console.error("founder profile lookup failed");
    return json({ error: "gift_processing_error" }, 500);
  }
  const unlimited =
    (founderProfile as { founder_unlimited_currency?: unknown } | null)
      ?.founder_unlimited_currency === true;

  let res: { data: unknown; error: { message?: string } | null };
  try {
    res = await svc.rpc("process_gift_spend", {
      p_request_id: requestId,
      p_user_id: user.id,
      p_gift_id: g.id,
      p_gift_name: g.name,
      p_gift_icon: g.icon,
      p_gift_animation: g.animation_key,
      p_rarity_id: g.rarity_id,
      p_credits_per_unit: g.credits,
      p_amount: amount,
      p_live_id: liveId,
      p_receiver_id: receiverId,
      p_sender_name: user.name ?? null,
      p_unlimited: unlimited,
    });
  } catch {
    console.error("process_gift_spend exception");
    return json({ error: "gift_processing_error" }, 500);
  }

  if (res.error) {
    const message = res.error.message ?? "";
    console.error("process_gift_spend failed");
    if (message.includes("insufficient_credits")) {
      return json({ error: "insufficient_credits" }, 400);
    }
    if (message.includes("live_not_found")) {
      return json({ error: "live_not_found" }, 400);
    }
    if (message.includes("live_not_active")) {
      return json({ error: "live_not_active" }, 400);
    }
    if (message.includes("receiver_id_required")) {
      return json({ error: "receiver_id_required" }, 400);
    }
    if (message.includes("receiver_not_streamer")) {
      return json({ error: "receiver_not_streamer" }, 403);
    }
    if (message.includes("cannot_send_to_self")) {
      return json({ error: "cannot_send_to_self" }, 400);
    }
    if (message.includes("invalid_request_id")) {
      return json({ error: "invalid_request_id" }, 400);
    }
    if (message.includes("gift_unavailable")) {
      return json({ error: "gift_unavailable" }, 400);
    }
    if (message.includes("request_id_conflict")) {
      return json({ error: "request_id_conflict" }, 409);
    }
    if (message.includes("duplicate_in_progress")) {
      return json({ error: "duplicate_in_progress" }, 409);
    }
    if (message.includes("gift_earnings_failed")) {
      return json({ error: "creator_earnings_failed" }, 500);
    }
    if (requestId && message.includes("duplicate key")) {
      const existing = await findExistingGift(svc, user.id, requestId);
      if (existing) {
        const existingCredits = finiteNumber(existing.credits_total) ?? 0;
        if (
          existing.receiver_id !== null &&
          existingCredits > 0 &&
          !(await earningsSucceeded(
            svc,
            existing.id,
            existing.receiver_id,
            existingCredits,
          ))
        ) {
          console.error("process_gift_earnings failed for duplicate");
          return json({ error: "creator_earnings_failed" }, 500);
        }
        return json(duplicateResponse(g, existing));
      }
    }
    return json({ error: "gift_processing_error" }, 500);
  }

  const out = (res.data ?? {}) as SpendResult;
  const transactionId =
    typeof out.transaction_id === "string" ? out.transaction_id : "";
  const resultAmount = finiteNumber(out.amount);
  const creditsSpent = finiteNumber(out.credits_spent);
  const balance = finiteNumber(out.balance);
  if (
    out.ok !== true ||
    transactionId.length === 0 ||
    resultAmount === null ||
    creditsSpent === null ||
    balance === null ||
    resultAmount < 0 ||
    creditsSpent < 0 ||
    balance < 0
  ) {
    console.error("process_gift_spend returned an invalid result");
    return json({ error: "gift_processing_error" }, 500);
  }

  const resultUnlimited =
    typeof out.unlimited === "boolean" ? out.unlimited : unlimited;
  const needsEarnings =
    receiverId !== null &&
    creditsSpent > 0 &&
    !resultUnlimited &&
    out.earnings_processed !== true;

  if (
    needsEarnings &&
    !(await earningsSucceeded(svc, transactionId, receiverId, creditsSpent))
  ) {
    console.error("process_gift_earnings failed");
    return json({ error: "creator_earnings_failed" }, 500);
  }

  return json({
    ok: true,
    duplicate: out.duplicate === true,
    transaction_id: transactionId,
    gift: {
      id: g.id,
      name: g.name,
      icon: g.icon,
      animation_key: g.animation_key,
    },
    amount: resultAmount,
    credits_spent: creditsSpent,
    balance,
    unlimited: resultUnlimited,
  });
});
