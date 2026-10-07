# SISTEMA FINANCEIRO CENTRAL — Presentes e Ganhos de Criador

## Como o criador ganha

Quando um usuário envia um **presente** (edge `send-gift` → `process_gift_spend`,
pré-existente), o app chama **após** o gasto bem-sucedido:

```
process_gift_spend (já existia)  → presente atômico (remetente paga)
        │
        ▼  se receiverId && transaction_id && credits_spent > 0 && !unlimited
process_gift_earnings  (novo, idempotente, service role)
        │
        ├─ INSERT gift_earnings (gift_tx_id UNIQUE)   ← idempotência
        ├─ fee = fee_configs['gift.default'] (20%)
        ├─ net = credits_spent × (1 − fee)
        ├─ economy_adjust(grant, ref='gift', id=gift_tx_id)  → wallet do criador
        └─ creator_balances.available_credits += net
```

**Garantias:**

- Idempotente por `gift_tx_id` (retry não crédita duas vezes).
- Falha no cálculo/aplicação dos ganhos **não reverte o presente** (log + segue).
- Presentes vindos do fundador (`unlimited`) não geram ganho (`!unlimited`).
- Moeda entregue é **moeda virtual** (credits) — nunca dinheiro.

## Saldo do criador — `creator_balances`

| Coluna | Significado |
|---|---|
| `available_credits` | ganho líquido hoje resgatável (não negativo) |
| `pending_credits` | reservado por um pedido de resgate em análise |
| `withdrawn_credits` | total já liquidado manualmente pelo fundador |

**Nunca negativo:** todas as movimentações usam `FOR UPDATE` + check.

## Resgate (intenção) — `creator_payout_request(p_amount_credits)`

1. Valida `amount_credits` > 0 e ≤ `available_credits` (`insufficient_funds`).
2. `available -= amount` e `pending += amount` (reserva).
3. Cria `creator_payout_requests` com status `pending` + `finance_audit`.
4. Retorna `{ok, request_id, amount_credits}`.

> Resgate é **intenção registrada**, NÃO pagamento em dinheiro. A liquidação real
> (PIX/carteira) é feita manualmente pelo fundador fora do app; ao aprovar no
> painel o saldo vira `withdrawn`.

## Decisão do fundador — `admin_payout_decision(p_request_id, p_approve, p_note)`

- `approve=true` → `pending → paid`, `pending_credits → withdrawn_credits`.
- `approve=false` → `pending → rejected`, `pending_credits → available_credits`
  (devolve ao criador).
- `request_already_decided` impede decisão dupla.

## Histórico para o criador

- `my_creator_earnings(p_limit)` → lista dos gifts recebidos com status.
- `creator_balance()` → saldo available/pending/withdrawn.
- No extrato geral (`my_finance_history`), ganhos aparecem como `kind='earning'`
  (filtro "Presentes" da carteira) e resgates como `kind='payout'`.

## Verificação de consistência

A `finance_integrity_check` compara, por criador, o total de `gift_earnings`
crédito no `creator_balances` (`EARNINGS_MISMATCH` se divergir).

## Comissões

`fee_configs` se aplica:

| Chave | Taxa | Uso |
|---|---|---|
| `gift.default` | 20% | desconto sobre `credits_spent` ao computar ganho |
| `payout.default` | 0% | reservado para faturar resgates futuros |

As taxas ficam **no backend**; o app nunca conhece o valor bruto original senão
através das RPCs.