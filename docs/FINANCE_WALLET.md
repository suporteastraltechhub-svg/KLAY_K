# SISTEMA FINANCEIRO CENTRAL — Carteira Financeira (App)

**Tela:** `lib/screens/finance_wallet_screen.dart` — acessível de
`lib/screens/wallet_sheet.dart` → botão **"Ver carteira completa (comprar moedas,
ganhos, extratos)"**.

**Serviço:** `lib/services/finance_service.dart` — camada única de acesso às RPCs
financeiras, com `rpcOverride` estático `@visibleForTesting` para contratos de teste
sem rede.

## Saldo e Pacotes

- `_balanceCard` mostra o saldo de moedas: `AdminService.myWallet()['credits']`
  (fonte única: o backend).
- `_packageTile` renderiza cada pacote do `finance_catalog`. Exibe nome, bônus
  (`+ X credits`) e preço em **reais** formatado por `NumberFormat.currency
  (locale 'pt_BR', symbol 'R\$')` a partir de `price_cents` (centavos).
- Se `is_active=false` não aparece; catálogo vazio → "Sem dados disponíveis".

## Fluxo de Compra (honesto — sem cobrança fictícia)

1. `_startPurchase` → `create_coin_order(pkg, idempotencyKey: FinanceService
   .newIdempotencyKey())`. A chave única impede pedido duplicado em retry
   (backend devolve o pagamento original).
2. `_verifyOrder` abre o dialog **"Verificando transação..."**
   (`_ProcessingDialog`, não-dismissable).
3. Polling de `finance_order_status` (até 12× a cada 1,6s):
   - `paid | captured` → snackbar "Pagamento confirmado! Moedas entregues."
   - `failed` → snackbar de falha.
   - nenhum dos dois (timeout) → snackbar "ainda processando".
4. `_load()` re-centraliza saldo, histórico e ganhos.

## Ganhos de Criador

- `_earningsCard`: `available_credits`, `pending_credits`, `withdrawn_credits`
  (fonte: `creator_balance`). Se não houver ganhos → "Sem dados disponíveis".
- Botão **"Solicitar resgate"** (só quando `available > 0`) → dialog
  `_askPayout` → `requestPayout(amount)`. É uma **intenção**; a liquidação real é
  manual pelo fundador.

## Histórico e Filtros

`my_finance_history` traz extrato consolidado; a tela filtra localmente:

| Índice | Filtro `financeFilter*` | Regra |
|---|---|---|
| 0 | Todos | todos |
| 1 | Entradas | `earning` OU `order` com status `paid` |
| 2 | Saídas | `refund` OU `payout` |
| 3 | Compras | `order` |
| 4 | Presentes | `earning` |
| 5 | Reembolsos | `refund` |

Cada tile mostra label por `kind` (`financeKindOrder/Earning/Refund/Payout`),
valor com sinal (`+`/`-`) e, para compras, o preço pago em reais.

## Estados de erro

- Falha de rede em `_load` → `_buildError` com "Não foi possível carregar a
  carteira." + botão "Tentar novamente".
- Chamadas opcionais (`_safeWallet`, `_safe`) nunca quebram a tela.

## Testes

`test/finance_test.dart` (21 testes):

- **Contrato RPC** (15): verifica `name` + params exatos enviados para
  `finance_catalog`, `create_coin_order` (package/idempotency/method),
  `finance_order_status`, `my_finance_history`, `creator_balance`,
  `creator_payout_request`, `admin_finance_stats`, `admin_price_update`,
  `finance_refund`, `finance_integrity_check`, `admin_payout_decision` e o
  mapeamento de `friendlyError`/`newIdempotencyKey`.
- **UI** (6): estado vazio, erro+retry, renderização de pacotes com preço,
  filtros "Compras" e "Reembolsos", e fluxo completo de compra
  (criar pedido → "Verificando transação..." → "Pagamento confirmado!").

Os testes de widget usam **delegates l10n reais** (locale `pt`) — não strings
hardcoded — e injetam backend fake via `rpcOverride` (sem rede).