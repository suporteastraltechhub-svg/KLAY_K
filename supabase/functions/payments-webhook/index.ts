import { createClient } from "npm:@supabase/supabase-js@^2";
import { json, opts } from "../_shared/cors.ts";

// ============================================================================
// KLAY K — Payments Webhook (Edge Function)
//
// Recebe notificações do provedor de pagamento (PSP). Valida assinatura
// HMAC-SHA256 contra o segredo armazenado em `payment_provider_config` e
// chama `finance_webhook_capture` (service_role) que é idempotente:
//   * 1ª entrega: credita moedas + marca order paid.
//   * Replay: devolve o mesmo resultado, sem re-creditar.
//
// Assinatura esperada: header `X-Webhook-Signature` contendo o hex digest
// de HMAC-SHA-256(webhook_secret, rawBody).
//
// POST /payments-webhook
//   body: {
//     event_id: string,       // id único do evento no PSP
//     type: 'payment.paid' | 'payment.failed',
//     provider_tx_id: string,
//     amount_cents: number,
//     provider: 'default'
//   }
//   header: X-Webhook-Signature: <hex>
// ============================================================================

function toHex(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacVerify(
  secret: string,
  body: string,
  signature: string,
): Promise<boolean> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(body));
  return toHex(sig) === signature.toLowerCase();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return opts();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const rawBody = await req.text();
  const sigHeader = req.headers.get("X-Webhook-Signature") ?? "";

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const eventType = typeof body.type === "string" ? body.type : "";
  const eventId = typeof body.event_id === "string" ? body.event_id.trim() : "";
  const providerTxId = typeof body.provider_tx_id === "string"
    ? body.provider_tx_id.trim()
    : "";
  const amountRaw = typeof body.amount_cents === "number"
    ? Math.round(body.amount_cents)
    : null;
  const provider = typeof body.provider === "string" && body.provider.trim()
    ? body.provider.trim()
    : "default";

  if (!eventId || eventId.length < 8) {
    return json({ error: "missing_event_id" }, 400);
  }
  if (!providerTxId) {
    return json({ error: "missing_provider_tx_id" }, 400);
  }

  const svc = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") as string,
  );

  // Busca o segredo de webhook do provider config.
  const { data: cfg, error: cfgErr } = await svc
    .from("payment_provider_config")
    .select("webhook_secret")
    .eq("id", provider)
    .eq("active", true)
    .maybeSingle();

  if (cfgErr || !cfg?.webhook_secret) {
    console.error("payments-webhook: provider config not found", cfgErr);
    return json({ error: "provider_not_configured" }, 500);
  }

  // Valida HMAC-SHA256.
  let signatureOk = false;
  if (sigHeader) {
    signatureOk = await hmacVerify(cfg.webhook_secret, rawBody, sigHeader);
  }

  // Mapeia tipo do evento → status para `finance_webhook_capture`.
  let captureStatus: string;
  if (eventType.startsWith("payment.paid") || eventType === "payment.captured") {
    captureStatus = "captured";
  } else if (
    eventType.startsWith("payment.failed") ||
    eventType === "payment.declined" ||
    eventType === "payment.voided"
  ) {
    captureStatus = "failed";
  } else {
    captureStatus = eventType;
  }

  try {
    const { data, error } = await svc.rpc("finance_webhook_capture", {
      p_event_id: eventId,
      p_provider: provider,
      p_provider_tx_id: providerTxId,
      p_status: captureStatus,
      p_signature_ok: signatureOk,
      p_amount_cents: amountRaw,
      p_payload: body,
    });

    if (error) {
      console.error("payments-webhook: capture error", error.message);
      return json({ error: "capture_failed", message: error.message }, 400);
    }

    const result = (data ?? {}) as { ok?: boolean; duplicate?: boolean };
    return json({
      ok: result.ok ?? false,
      duplicate: result.duplicate ?? false,
      event_id: eventId,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("payments-webhook: exception", msg);
    return json({ error: "internal_error", message: msg }, 500);
  }
});
