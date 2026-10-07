# SISTEMA FINANCEIRO CENTRAL — Pedidos, Pagamentos e Webhook

## Fluxo de compra (backend)

```
Flutter                        SUPABASE (PostgreSQL)              Provedor / Edge
  │  create_coin_order  ──────────►│
  │                                │ 1. Valida args + `economy_has_admin`? não.
  │                                │ 2. SELECT package FOR UPDATE (price, credits)
  │                                │ 3. INSERT financial_orders (draft→pending)
  │                                │ 4. INSERT financial_payments
  │                                │    (idempotency_key UNIQUE)
  │                                │ 5. RETORNA {order_id, payment_id, price…}
  │◄────────────────  pedido criado │
  │                                │
  │  payments-webhook (posterior) ─┼─────────────► pay(provider)
  │                                │  HMAC X-Webhook-Signature + event_id
  │                 finance_webhook_capture ◄── edge (service_role)
  │                                │ 1. INSERT payment_webhook_events (PK)
  │                                │    → replay devolve resultado já capturado
  │                                │ 2. Confere status/assinatura (edge)
  │                                │ 3. Confere amount_cents (amount_mismatch)
  │                                │ 4. FOR UPDATE payment+user wallet
  │                                │ 5. economy_adjust(grant, ref purchase) =
  │                                │    ENTREGA DAS MOEDAS (uma única vez)
  │                                │ 6. order → paid, payment → captured
  │  finance_order_status (poll)  ─►│
  │◄────────────────  paid/captured │
```

## `create_coin_order(p_package_id, p_idempotency_key, p_method)`

- `security definer`, caller `authenticated` (qualquer usuário logado).
- `p_idempotency_key` + `p_method` publicados; `p_package_id` public.
- Preço/créditos lidos **do catálogo com `FOR UPDATE`** (nunca do cliente).
- Retry com a mesma chave → devolve o mesmo `payment` (`duplicate: true`),
  sem criar pedido novo.

## `finance_webhook_capture(...)` — capture idempotente

- `security definer`, EXECUTE restrito a `service_role` (edge `payments-webhook`).
- `event_id` único → INSERT em `payment_webhook_events`.
  - Conflito (replay) → devolve o resultado já processado, sem reentregar moedas.
- Conferência de valor: `amount_cents` deve **bater exatamente** com o pedido;
  caso contrário `amount_mismatch` (não captura, registra antifraud flag).
- Entrega via `economy_adjust(kind='grant', ref='purchase', id=order_id)`.
- Concorrência: transação + `FOR UPDATE` na linha do pagamento => única entrega.

## Edge function `payments-webhook`

`supabase/functions/payments-webhook/index.ts`:

- `POST` + header `X-Webhook-Signature` (hex HMAC-SHA256) comparado ao
  `webhook_secret` em `payment_provider_config` (service role; o cliente **não**
  tem acesso). Assinatura inválida → `401` e **não captura**.
- Corpo esperado: `{ event_id, type, provider_tx_id, amount_cents, provider }`.
- Mapeamento de eventos do provedor:
  - `payment.paid` → `captured`
  - `payment.failed` / `payment.declined` / `payment.voided` → `failed`
- Toda captura passa por `finance_webhook_capture` (idempotente).

> **Importante (sem gateway falso):** o app exibe o flow "Verificando
> transação..." e **nunca assume** que o pagamento ocorreu. O webhook é o único
> ponto que move moedas; se o provedor não assinar/cobrar, o pedido permanece
> `pending` e o usuário não recebe moedas.

## Reembolso — `finance_refund(p_payment_id, p_reason)`

- Admin/fundador (cap `economy`).
- Pag 5 estado só é reembolsável se `captured` e não reembolsado antes.
- Cria `financial_refunds`, chama `economy_adjust(kind='refund', …)` para
  *devolver* as moedas **para o mesmo usuário**, e marca o pagamento `refunded`.
- Registra no histórico financeiro (filtro "Reembolsos").

## Estados

- `financial_orders.status`: `draft | pending | paid | failed | refunded | cancelled`
- `financial_payments.status`: `pending | captured | failed | refunded |
  cancelled`
- Invariante central: **pedido `paid` ⇒ pagamento `captured` e moedas entregues
  exatamente uma vez** (garantido pelo `finance_integrity_check`).