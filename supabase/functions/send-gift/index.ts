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

const MAX_AMOUNT = 999;

function giftAvailable(g: RichGift, now: number): boolean {
  if (g.status !== "active") return false;
  if (g.featured_start && new Date(g.featured_start).getTime() > now) return false;
  if (g.featured_end && new Date(g.featured_end).getTime() < now) return false;
  return true;
}

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

  const giftId = typeof body.gift_id === "string" ? body.gift_id.trim() : "";
  const amountRaw =
    typeof body.amount === "number" ? Math.floor(body.amount) : 1;
  const amount = Math.max(1, Math.min(amountRaw, MAX_AMOUNT));
  const liveId = typeof body.live_id === "string" ? body.live_id : null;
  const receiverId = typeof body.receiver_id === "string"
    ? body.receiver_id
    : null;
  const requestId = typeof body.request_id === "string" &&
      body.request_id.trim().length >= 8 && body.request_id.trim().length <= 64
    ? body.request_id.trim()
    : null;

  if (!giftId) return json({ error: "gift_required" }, 400);

  const svc = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );

  const { data: gift, error: giftErr } = await svc
    .from("gifts")
    .select(
      "id,name,credits,status,icon,animation_key,rarity_id,is_tradable,is_limited,event_id,featured_start,featured_end,event_id",
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

  const senderId = user.id;
  if (receiverId && receiverId === senderId) {
    return json({ error: "cannot_send_to_self" }, 400);
  }

  const totalCredits = g.credits * amount;

  // Idempotência: o request_id é "clamado" primeiro (RPC atômica security
  // definer). Somente o vencedor debita/envia; uma nova tentativa com o mesmo
  // id reaproveita a transação gravada, evitando débito duplo em retry.
  if (requestId) {
    const { data: claimed, error: claimErr } = await svc.rpc(
      "claim_gift_request",
      { p_request_id: requestId, p_user_id: senderId },
    );

    if (claimErr || claimed !== true) {
      const { data: existing } = await svc.from("gift_transactions").select(
        "id,gift_id,gift_name,amount,credits_total,balance_after",
      ).eq("request_id", requestId).maybeSingle();

      if (existing) {
        return json({
          ok: true,
          duplicate: true,
          transaction_id: existing.id,
          gift: {
            id: existing.gift_id,
            name: existing.gift_name,
            icon: g.icon,
            animation_key: g.animation_key,
          },
          amount: existing.amount,
          credits_spent: existing.credits_total,
          balance: existing.balance_after,
        });
      }
      // Request clameado antes do débito mas ainda sem transação gravada:
      // cliente deve tentar de novo com um request_id novo (sem efeito).
      return json({ error: "duplicate_in_progress" }, 409);
    }
  }

  // Fundador com créditos ilimitados (flag server-side): NÃO debita saldo, mas
  // ainda registra a transação (balance_after = saldo atual, inalterado). A
  // decisão de dar créditos ilimitados é exclusiva do backend (founder flag),
  // nunca do cliente.
  const { data: founderProfile } = await svc
    .from("profiles")
    .select("founder_unlimited_currency")
    .eq("id", senderId)
    .maybeSingle();
  const unlimited =
    typeof founderProfile?.founder_unlimited_currency === "boolean"
      ? founderProfile.founder_unlimited_currency
      : false;

  let balanceAfter: number;
  if (unlimited) {
    const { data: cur } = await svc
      .from("user_wallets")
      .select("credits")
      .eq("user_id", senderId)
      .maybeSingle();
    balanceAfter = typeof cur?.credits === "number" ? cur.credits : 0;
  } else {
    // Deduz créditos de forma atômica num RPC do Postgres (saldos garantidos
    // pelo banco: só prossegue se houver saldo suficiente).
    const { data: debit, error: debitErr } = await svc.rpc("debit_credits", {
      p_user_id: senderId,
      p_delta: totalCredits,
    });

    if (debitErr || !debit || typeof debit.balance !== "number") {
      console.error("debit_credits error:", debitErr?.message ?? "no balance");
      return json({ error: "insufficient_credits", reason: debitErr?.message }, 400);
    }
    balanceAfter = debit.balance;
  }

  // Registra o ledger de créditos (débito 0 para o fundador ilimitado —
  // transação registrada, saldo intacto).
  await svc.from("credit_transactions").insert({
    user_id: senderId,
    delta: unlimited ? 0 : -totalCredits,
    balance_after: balanceAfter,
    kind: "spend",
    ref_type: "gift",
    ref_id: `${giftId}:${amount}`,
    note: `Envio de ${g.name} x${amount}${unlimited ? " (fundador ilimitado)" : ""}`,
  });

  // Registra o histórico financeiro autoritativo do envio.
  const { data: tx } = await svc.from("gift_transactions").insert({
    user_id: senderId,
    receiver_id: receiverId,
    live_id: liveId,
    gift_id: g.id,
    gift_name: g.name,
    amount,
    credits_per_unit: g.credits,
    credits_total: totalCredits,
    balance_after: balanceAfter,
    request_id: requestId,
  }).select("id").single();

  // Se o envio ocorreu numa live, registra o presente recebido (feed real do
  // app usa live_gifts + live_events) e o evento do chat.
  if (liveId) {
    const chatLine =
      `🎁 ${user.name ?? "Alguém"} enviou ${g.icon} ${g.name} x${amount}`;
    await svc.from("live_chat").insert({
      live_id: liveId,
      user_id: senderId,
      message: chatLine,
    });
    await svc.from("live_gifts").insert({
      live_id: liveId,
      sender_id: senderId,
      receiver_id: receiverId,
      gift_id: g.id,
      gift_name: g.name,
      gift_amount: amount,
    });
    await svc.from("live_events").insert({
      live_id: liveId,
      event_type: "GIFT_RECEIVED",
      user_id: senderId,
      username: user.name ?? null,
      metadata: {
        gift_id: g.id,
        gift_name: g.name,
        gift_icon: g.icon,
        gift_amount: amount,
        gift_animation: g.animation_key,
        rarity_id: g.rarity_id,
        message: chatLine,
      },
    });

    // Notificação ao streamer/usuário que recebeu.
    if (receiverId) {
      await svc.from("notifications").insert({
        user_id: receiverId,
        actor_id: senderId,
        type: "gift",
        ref_id: tx?.id ?? null,
        message: `${user.name ?? "Alguém"} enviou ${g.icon} ${g.name} x${amount}`,
      });
    }
  }

  // Atualiza estatísticas do presente (populares/tendências/recomendados).
  const { data: stats } = await svc.from("gift_usage_stats").select("sent_count")
    .eq("gift_id", g.id).maybeSingle();
  const sentCount = (stats?.sent_count ?? 0) + amount;
  await svc.from("gift_usage_stats").upsert({
    gift_id: g.id,
    sent_count: sentCount,
    last_sent_at: new Date().toISOString(),
  });

  return json({
    ok: true,
    transaction_id: tx?.id ?? null,
    gift: {
      id: g.id,
      name: g.name,
      icon: g.icon,
      animation_key: g.animation_key,
    },
    amount,
    credits_spent: unlimited ? 0 : totalCredits,
    balance: balanceAfter,
    unlimited,
  });
});
