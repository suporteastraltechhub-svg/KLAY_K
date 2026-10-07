# SISTEMA FINANCEIRO CENTRAL — Painel do Fundador

A seção **FINANCEIRO** (`_financeSection`) fica dentro da aba Econômia do
`FounderPanelScreen` (`lib/screens/founder_panel_screen.dart`) e só renderiza
para quem tem cap `economy` (validado no backend por `economy_has_admin`).

## Sumários — `admin_finance_stats()`

| Card | Campo | Fonte |
|---|---|---|
| Pedidos | `orders_total` | total de `financial_orders` |
| Pagos (confirmados) | `orders_paid` | status `paid` |
| Receita | `revenue_cents` | soma BRL capturados |
| Ganhos de criador | `gift_net_credits` | total líquido de `gift_earnings` |
| Comissões de presentes | `gift_fees_credits` | total de taxas retidas |
| Criadores disponíveis | `creator_available` | soma `available_credits` |

Tudo exibido com `_centsToReais` (centavos → BRL) quando aplicável.

## Resgates pendentes — `admin_list_payouts()`

- Lista `creator_payout_requests` com status `pending` e nome do usuário.
- `_payoutTile`: **Aprovar** → `admin_payout_decision(approve: true)` e
  **Rejeitar** → `admin_payout_decision(approve: false)`.
- Sem pendências → "Sem resgates pendentes".
- Confirmação visual (dialog) antes da decisão; recarregamento ao final.

> A aprovação finaliza a **intenção** (saldo → withdrawn). A liquidação em
> dinheiro acontece fora do app, manualmente, como combinado.

## Pedidos recentes — `admin_finance_orders()`

- Lista dos últimos pedidos com status, usuário e preço (`_financeOrderTile`).
- Cores por status (paid verde / failed vermelho / pending âmbar).

## Verificação de integridade — `finance_integrity_check()`

- Card com botão "Executar verificação de integridade".
- `_checkIntegrity`: abre dialog com resultado:
  - Sem anomalias → "Integridade financeira correta".
  - Com anomalias → "Alerta de integridade financeira" + contagem das anomalias
    via `l10n.financeIntegrityResult(count)`.

## Alteração de preço — `admin_price_update(p_package_id, p_new_price_cents, p_reason)`

- Só admin (cap `economy`).
- Escreve em `financial_price_history` (trilha auditável de cada mudança).
- Clientes sempre consomem o preço **atual** do catálogo (nunca um valor local).

## Segurança no painel

- Toda RPC admin usada aqui tem `security definer` e valida internamente
  `has_perm/... 'economy' Admin`) → caller sem cap recebe `not_admin`, mesmo que
  o app esconda a seção.
- `FinanceService.friendlyError('not_admin')` → "Permissão negada pelo servidor."