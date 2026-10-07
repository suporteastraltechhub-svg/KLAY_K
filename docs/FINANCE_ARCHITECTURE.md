# SISTEMA FINANCEIRO CENTRAL — Visão Geral (Finanças)

> Documento de arquitetura do **KLAY K FINANCE**: o subsistema que conecta moedas
> virtuais (compra, pacotes, presentes) à contabilidade financeira (pedidos,
> pagamentos, reembolsos, ganhos de criador, resgates e faixas de integridade).

**Documentos relacionados:** [WALLET](FINANCE_WALLET.md) ·
[PAYMENTS](FINANCE_PAYMENTS.md) · [GIFTS_EARNINGS](FINANCE_GIFTS_EARNINGS.md) ·
[FOUNDER_PANEL](FINANCE_FOUNDER_PANEL.md) · [SECURITY](FINANCE_SECURITY.md)

---

## 1. Cobertura

| Área | Status | Onde |
|---|---|---|
| Economia multi-moeda (6 moedas) + ledger | Pré-existente | `user_wallets` + `credit_transactions` + `economy_adjust` |
| Catálogo de pacotes de moedas (compra) | **Novo** | `coin_packages` + `create_coin_order` |
| Pedidos e pagamentos idempotentes | **Novo** | `financial_orders` / `financial_payments` |
| Webhook de pagamento (HMAC-SHA256) | **Novo** | edge `payments-webhook` + `finance_webhook_capture` |
| Histórico de preços (mudanças de pacote) | **Novo** | `financial_price_history` + `admin_price_update` |
| Reembolsos administrados | **Novo** | `financial_refunds` + `finance_refund` |
| Ganhos de criador por presente | **Novo** | `gift_earnings` + `process_gift_earnings` |
| Saldo e resgates de criador | **Novo** | `creator_balances` + `creator_payout_requests` |
| Taxas de plataforma | **Novo** | `fee_configs` (gift 20%, payout 0%) |
| Antifraude básica | **Novo** | `antifraud_flags` + `finance_classify_user` |
| Verificação de integridade ledger×wallet | **Novo** | `finance_integrity_check` |

## 2. Regra de ouro

> **O backend decide SEMPRE o dinheiro.** Preço, quantidade de moedas, destinatário,
> moeda e taxas são resolvidos em RPCs `security definer`. O app Flutter nunca
> calcula saldo/preço; ele apenas envia identidade (`p_*` params) e muda estados.
>
> **Dinheiro REAL × moeda VIRTUAL ficam separados:**
> - Preço em centavos (`numeric`) existe SÓ no backend (nunca no dispositivo).
> - A entrega ao usuário é SEMPRE moeda virtual via `economy_adjust`.
> - Resgate de criador é uma **intenção registrada**; a liquidação real acontece
>   manualmente pelo fundador, fora do app.

## 3. Camadas

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter                                                      │
│  FinanceService (lib/services/finance_service.dart)           │
│  FinanceWalletScreen + Founder Panel (_financeSection)        │
│  WalletSheet → "Ver carteira completa"                        │
├─────────────────────────────────────────────────────────────┤
│  Edge Functions                                               │
│  send-gift → process_gift_earnings (ganhos de criador)        │
│  payments-webhook → finance_webhook_capture (captura)         │
├─────────────────────────────────────────────────────────────┤
│  Supabase (PostgreSQL)                                        │
│  11 tabelas financeiras + 17 RPCs `security definer` + RLS    │
│  Reusa economy_adjust / process_gift_spend / audit_logs       │
└─────────────────────────────────────────────────────────────┘
```

## 4. Tabelas (11 + seeds)

| Tabela | Finalidade | Destaques |
|---|---|---|
| `coin_packages` | Catálogo vendável | seeds: pack_100 (R$1,99), pack_500 (R$9,49), pack_1200 (R$19,99), pack_3000 (R$45,99) |
| `financial_price_history` | Trilha de mudanças de preço | escrita só por `admin_price_update` |
| `fee_configs` | Taxas de plataforma | gift default 20%, payout default 0% |
| `financial_orders` | Pedido do usuário | srta devolver moedas UMA vez (checks) |
| `financial_payments` | Pagamento do pedido | `idempotency_key` UNIQUE, `provider_tx_id` UNIQUE |
| `payment_webhook_events` | Replays do webhook | PK = `event_id`; sem grants ao cliente |
| `payment_provider_config` | Segredo de assinatura | `webhook_secret` gen_random_uuid; sem grants ao cliente |
| `financial_refunds` | Reembolsos administrados | usa `economy_adjust` kind `refund` |
| `gift_earnings` | Ganho por presente | `gift_tx_id` UNIQUE → idempotente |
| `creator_balances` | Saldo do criador | available / pending / withdrawn (não-negativo) |
| `creator_payout_requests` | Intenções de resgate | provado e decidido manualmente |

## 5. RPCs (17)

- Catálogo/pedidos: `finance_catalog`, `create_coin_order`, `finance_order_status`, `my_finance_history`, `my_creator_earnings`, `creator_balance`
- Pagamento/webhook: `finance_webhook_capture` (service_role), `finance_refund`
- Criador: `process_gift_earnings` (service_role, baseado em gift), `creator_payout_request`
- Admin/fundador: `admin_finance_stats`, `admin_finance_orders`, `admin_price_update`, `admin_list_payouts`, `admin_payout_decision`, `finance_integrity_check`, `finance_classify_user`

Todas são `security definer`; o cap `economy`/admin é validado internamente
via `has_perm`/`economy_has_admin` (fundador imutável `ceo.arh.tech@gmail.com`).

## 6. Idempotência e concorrência

- Pedido duplicado: `idempotency_key` UNIQUE → retry devolve o pagamento original.
- Webhook duplicado: PK `event_id` → replay devolve o resultado já capturado.
- Ganho de presente duplicado: `gift_tx_id` UNIQUE.
- Toda movimentação usa **transação** + `FOR UPDATE` (linhas: pedido, wallet,
  saldo do criador) e CHECK `< saldo >= 0` para nunca criar negativo.

## 7. Verificação de integridade

`finance_integrity_check` (somente admin) cruza 4 conjuntos de anomalias:

1. `LEDGER_MISMATCH` — soma do ledger ≠ saldo das wallets.
2. `ORDER_NOT_PAID` — pedido entregue sem pagamento capturado.
3. `PARTIAL_DELIVERY` — pagamento capturado sem entrega completa.
4. `EARNINGS_MISMATCH` — ganho de gift registrado ≠ crédito no `creator_balances`.

Se houver anomalias: `FINANCIAL_INTEGRITY_ALERT` (nisso o Founder Panel mostra).