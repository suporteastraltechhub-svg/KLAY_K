# SISTEMA FINANCEIRO CENTRAL — Segurança

> Regra que governa todo o KLAY K FINANCE: **Nunca confie no cliente.**
> Saldo, preço, quantidade, destinatário, moeda e taxas existem SÓ no backend;
> o app apenas envia identidade.

## 1. RLS (Row Level Security)

- **Cliente (authenticated)**: só RPCs `security definer` — sem INSERT/UPDATE/
  DELETE direto em tabelas financeiras.
- `payment_provider_config`, `payment_webhook_events` e `antifraud_flags`:
  **nenhum grant ao cliente** (nem leitura). O segredo de assinatura
  (`webhook_secret`) é visível apenas para `service_role`.
- Tabelas `financial_*`, `coin_packages` (leitura), `gift_earnings`,
  `creator_balances`, `creator_payout_requests`: leitura restrita ao dono ou
  exposta apenas via RPC que filtra por `auth.uid()`.
- Grants: somente os mínimos para `anon`/`authenticated` + `service_role`.

## 2. Confiança zero no cliente

| O que o cliente envia | O que o backend decide |
|---|---|
| `p_method` (p. ex. `card`) | Valida o método |
| `p_package_id` | **Preço, créditos e moeda** lidos do catálogo (`FOR UPDATE`) |
| `idempotency_key` | Uso único via UNIQUE, sem criar pedido duplicado |
| `p_amount_credits` (resgate) | Checado contra `available_credits` (≥ 0) |

O parâmetro `amount_cents` no webhook é o **preço** do pedido gravado; qualquer
divergência → `amount_mismatch` + `antifraud_flag`.

## 3. Webhook — assinatura e idempotência

- Header `X-Webhook-Signature` = hex HMAC-SHA256 do body **com segredo em
  `payment_provider_config`** (lido com `service_role`, nunca exposto).
- Assinatura inválida → `401`, NADA é capturado (`bad_signature`).
- `event_id` é PK de `payment_webhook_events`: replay devolve o resultado já
  processado, **sem** reentregar moedas.
- `provider_tx_id` UNIQUE bloqueia eventos duplicados de mesma transação.

## 4. Concorrência e atomicidade

- Toda movimentação que ajuda moedas roda em **transação** com `FOR UPDATE`
  (linha do pedido/pagamento, wallet, `creator_balances`) + CHECK de não-negativo:
  impossível creditar duas vezes ou ficar negativo sob concorrência.
- `economy_adjust` (pré-existente) tem a mesma proteção (CHECK/BALANCE).

## 5. Funções `security definer`

- `create_coin_order`, `finance_webhook_capture`, `process_gift_earnings`,
  `creator_payout_request`, `finance_refund`, `finance_integrity_check`,
  `admin_*`, `finance_classify_user`…
  - `search_path` fixo `public`; corpo validaCap/identidade antes de ler dados.
  - Execução de webhook/capture restrita a `service_role` (edges já são service
    role) — `revoke execute` para qualquer outro role.
- O papo de fundador (`ceo.arh.tech@gmail.com`) é imutável por trigger
  (`founder_unlimited_currency` / `has_perm`), garantindo que nunca se perca o
  `economy` admin.

## 6. Antifraude — `finance_classify_user(p_user_id)`

- Calcula nível (`NORMAL` / observado / crítico) combinando peso e volume de
  flags em `antifraud_flags` (ativo) do usuário.
- Uso típico: compra suspeita marca flags; capturas/reembolsos gravam
  `antifraud_flags` (ex.: `amount_mismatch`, `bad_signature`).
- Só é chamável por RPC; o app nunca calcula nível localmente (fallback
  `NORMAL`).

## 7. Testes das garantias

- `test/finance_test.dart`: verifica parâmetros exatos enviados ao backend
  (sem inventar preço/saldo no app) e que estados de erro → mensagens amigáveis.
- Backend: verificado por simulação/manual das RPCs; a `finance_integrity_check`
  serve de saneamento periódico (ledger vs wallet, pedido pago sem entrega,
  ganhos vs saldo do criador).