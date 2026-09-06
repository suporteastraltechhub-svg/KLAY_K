-- ============================================================================
-- KLAY K — TESTE SEGURO: FUNDADOR ILIMITADO + CONVERSÃO DE MOEDAS
-- (totalmente reversível, NÃO altera saldos reais de usuários)
--
-- COMO USAR:
--   1) Rode no SQL Editor do Supabase (conecta como postgres/service role).
--   2) Pole o resultado em 3 seções: [A] verificação / [B] simulação / [C] limpeza.
--   3) No final, CONFIRME a mensagem de "LIMPEZA OK".
--
-- SEGURANÇA DESTE SCRIPT:
--   * Nenhum UPDATE/INSERT/DELETE em perfis ou carteiras de usuários reais.
--   * Os saldos e pedidos são criados num USUÁRIO TEMPORÁRIO descartável,
--     com email fixo 'klayk.test.founder@example.invalid', criado e APAGADO
--     aqui. O DELETE em auth.users cascateia (on delete cascade) para perfil,
--     carteira, ledger e pedidos de conversão deste usuário.
--   * A regra de conversão de teste é criada e depois APAGADA.
--   * O fundador REAL (ceo.arh.tech@gmail.com) só é LIDO — nunca alterado.
--
-- OBSERVAÇÃO IMPORTANTE: as RPCs de conversão (currency_conversion_request,
-- admin_conversion_decision, cancel_conversion_request) só funcionam com um
-- JWT autenticado (usam auth.uid()). No SQL Editor isso é NULL, então este
-- script SIMULA a mecânica (economy_adjust + reserva + aprovação/refund)
-- diretamente, provando a aritmética e a individualização do saldo. O caminho
-- RPC completo da ponta a ponta é validado no APP (etapa guiada no final).
-- ============================================================================

set search_path = public;

-- ============================================================================
-- [A] VERIFICAÇÃO (somente leitura + criação de regra de teste removível)
-- ============================================================================

-- A1) Objetos da migration existem?
select 'A1: objetos da migration' as etapa;
select 'currency_conversion_requests' as objeto,
       to_regclass('public.currency_conversion_requests') is not null as existe_ok
union all
select 'conversion_settings',
       to_regclass('public.conversion_settings') is not null
union all
select 'tg_founder_unlimited_guard',
       to_regprocedure('public.tg_founder_unlimited_guard()') is not null;

-- A2) Fundador real: flag ilimitada + selo (SOMENTE LEITURA)
select 'A2: fundador real (somente leitura)' as etapa;
select u.email,
       p.founder_unlimited_currency,
       p.is_verified,
       p.is_admin,
       p.role
  from auth.users u
  join public.profiles p on p.id = u.id
 where lower(u.email) = 'ceo.arh.tech@gmail.com';

-- A3) Imutabilidade da flag: TODO perfil NÃO-fundador deve estar false.
--     (Se houver algum true que não seja o email oficial, o trigger falhou.)
select 'A3: imutabilidade da flag' as etapa,
       count(*) filter (where p.founder_unlimited_currency = true
                         and lower(u.email) <> 'ceo.arh.tech@gmail.com') as vazamentos,
       count(*) as total_perfis
  from auth.users u
  join public.profiles p on p.id = u.id;

-- A4) Regras de conversão ativas (RPC my_conversion_settings, security definer)
select 'A4: regras ativas atuais' as etapa;
select id, name, from_currency, to_currency, rate, fee_percent, status
  from public.my_conversion_settings();

-- ---------------------------------------------------------------------------
-- Criação da REGRA DE TESTE (removível; deletada em [C]).
-- Regra: 10 CREDITS -> 50 DIAMONDS  (rate 5,0; min 10; max 1000; sem taxa)
-- ---------------------------------------------------------------------------
insert into public.conversion_settings
  (id, name, from_currency, to_currency, rate, min_amount, max_amount,
   fee_percent, status, method, description, sort_order)
values
  ('test-kred-2-diam', 'Teste: Créditos -> Diamantes', 'credits', 'diamonds',
   5.0, 10, 1000, 0, 'active', 'wallet', 'Regra de teste (removida ao fim)', 0)
on conflict (id) do update set
  name = excluded.name, from_currency = excluded.from_currency,
  to_currency = excluded.to_currency, rate = excluded.rate,
  min_amount = excluded.min_amount, max_amount = excluded.max_amount,
  fee_percent = excluded.fee_percent, status = excluded.status,
  method = excluded.method, description = excluded.description;

select 'A5: regra de teste inserida' as etapa;
select id, from_currency, to_currency, rate, min_amount, max_amount
  from public.conversion_settings where id = 'test-kred-2-diam';

-- ============================================================================
-- [B] SIMULAÇÃO DA MECÂNICA COM USUÁRIO TEMPORÁRIO DESCARTÁVEL
-- ============================================================================

-- B1) Cria usuário temporário (NÃO é o fundador; sem email real).
--     O trigger grant_initial_credits dá 100 credits de boas-vindas.
--     (Colunas opcionais mais novas ficam com o default do Supabase.)
select 'B1: criação de usuário temporário' as etapa;
insert into auth.users (
    instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, confirmation_token, recovery_token,
    email_change_token_new, email_change,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, id
)
values (
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'klayk.test.founder@example.invalid',
    crypt('Temporario#9z!', gen_salt('bf')),
    now(), '', '', '', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(), now(), '00000000-0000-0000-0000-00000000e001'
)
on conflict (id) do nothing;

-- Perfil para o usuário temporário (necessário p/ leitura coesa; NÃO é o fundador,
-- logo founder_unlimited_currency = false pelo trigger de guarda).
insert into public.profiles (id, username, display_name, created_at)
values (
    '00000000-0000-0000-0000-00000000e001',
    'klayk_test_founder', 'KLAY K Test Founder', now()
)
on conflict (id) do update set username = excluded.username;

-- B2) Confirma que o usuário temporário NÃO é ilimitado (trigger funcionou).
select 'B2: temporário não é fundador (flag=false)' as etapa;
select u.email, p.founder_unlimited_currency as ilimitado_esperado_false
  from auth.users u
  join public.profiles p on p.id = u.id
 where u.id = '00000000-0000-0000-0000-00000000e001';

-- B3) Adiciona saldo de TESTE (não é saldo de usuário real): +500 credits.
--     economy_adjust é executável como service_role e grava no ledger.
do $$
declare v jsonb;
begin
  v := public.economy_adjust(
         '00000000-0000-0000-0000-00000000e001', 'credits', 500,
         'grant', 'system', 'test-setup', 'Saldo de teste (revertido no fim)');
end $$;

select 'B4: saldo de teste criado' as etapa;
select credits as credits_esperado_600, diamonds as diamonds_esperado_0
  from public.user_wallets where user_id = '00000000-0000-0000-0000-00000000e001';

-- B5) SIMULA o pedido de conversão (reserva): debita 100 credits da origem.
--     (Em produção isso acontece dentro da RPC currency_conversion_request,
--      com FOR UPDATE; aqui reproduzimos o mesmo economy_adjust de reserva.)
do $$
declare v jsonb;
begin
  v := public.economy_adjust(
         '00000000-0000-0000-0000-00000000e001', 'credits', -100,
         'spend', 'conversion', 'test-kred-2-diam',
         'Reserva para conversao -> diamonds (simulacao de teste)');
end $$;

-- Registra o "pedido" pendente na tabela de conversão (mesmo schema da RPC).
insert into public.currency_conversion_requests
  (id, user_id, setting_id, from_currency, to_currency, amount, rate, fee, received, status)
values (
  '00000000-0000-0000-0000-00000000e010',
  '00000000-0000-0000-0000-00000000e001',
  'test-kred-2-diam', 'credits', 'diamonds',
  100, 5.0, 0, 500, 'pending');

select 'B6: reserva efetuada (credits 600->500; pedido pending)' as etapa;
select credits as credits_apos_reserva_esperado_500,
       diamonds as diamonds_antes_aprovacao_esperado_0
  from public.user_wallets where user_id = '00000000-0000-0000-0000-00000000e001';

select id, status, amount, rate, fee, received
  from public.currency_conversion_requests
 where id = '00000000-0000-0000-0000-00000000e010';

-- B7) SIMULA a APROVAÇÃO: credita 500 diamonds na carteira do mesmo usuário.
--     (Na RPC admin_conversion_decision, o status vira 'executed' numa transação.)
do $$
declare v jsonb;
begin
  v := public.economy_adjust(
         '00000000-0000-0000-0000-00000000e001', 'diamonds', 500,
         'grant', 'conversion', '00000000-0000-0000-0000-00000000e010',
         'Recebido de conversao (origem ja reservada) - simulacao');
end $$;

update public.currency_conversion_requests
   set status = 'executed', decided_at = now()
 where id = '00000000-0000-0000-0000-00000000e010';

select 'B8: aprovação simulada (diamonds 0->500; status executed)' as etapa;
select credits as credits_final_500, diamonds as diamonds_final_500
  from public.user_wallets where user_id = '00000000-0000-0000-0000-00000000e001';

-- B9) Demonstrativo de REJEIÇÃO/REFUND numa segunda reserva (garante o
--     caminho de reversão sem double-spend): reserva 50 credits e reembolsa.
do $$
declare v jsonb;
begin
  v := public.economy_adjust(
         '00000000-0000-0000-0000-00000000e001', 'credits', -50,
         'spend', 'conversion', 'test-kred-2-diam',
         'Reserva p/ demo de rejeicao (simulacao)');
  v := public.economy_adjust(
         '00000000-0000-0000-0000-00000000e001', 'credits', 50,
         'refund', 'conversion', 'test-kred-2-diam',
         'Reembolso por rejeicao (simulacao)');
end $$;

select 'B10: rejeição/refund ok (credits volta a 500)' as etapa;
select credits as credits_final_revertido_500
  from public.user_wallets where user_id = '00000000-0000-0000-0000-00000000e001';

select 'B11: ledger do usuário temporário (deve conter grant/spend/refund)' as etapa;
select delta, kind, ref_type, note
  from public.credit_transactions
 where user_id = '00000000-0000-0000-0000-00000000e001'
 order by created_at;

-- ============================================================================
-- [C] LIMPEZA — remove TODOS os dados de teste criados acima
-- ============================================================================

-- Deleta a regra de conversão de teste.
delete from public.conversion_settings where id = 'test-kred-2-diam';

-- Deleta o usuário temporário. ON DELETE CASCADE remove:
--   profiles, user_wallets, credit_transactions, currency_conversion_requests
delete from auth.users where id = '00000000-0000-0000-0000-00000000e001';

-- Confirma que não sobrou nada (todas devem retornar 0 / vazio).
select 'C: LIMPEZA' as etapa;
select
  (select count(*) from auth.users where id = '00000000-0000-0000-0000-00000000e001') as sobrou_auth_user_0,
  (select count(*) from public.profiles where id = '00000000-0000-0000-0000-00000000e001') as sobrou_profile_0,
  (select count(*) from public.user_wallets where user_id = '00000000-0000-0000-0000-00000000e001') as sobrou_wallet_0,
  (select count(*) from public.credit_transactions where user_id = '00000000-0000-0000-0000-00000000e001') as sobrou_ledger_0,
  (select count(*) from public.currency_conversion_requests where id = '00000000-0000-0000-0000-00000000e010') as sobrou_pedido_0,
  (select count(*) from public.conversion_settings where id = 'test-kred-2-diam') as sobrou_regra_0;

-- Sanidade final: saldo do fundador REAL não foi tocado neste script
-- (exibido só para conferência visual; nenhuma escrita ocorreu nele).
select 'C: conferência — fundador real intocado' as etapa;
select u.email, p.founder_unlimited_currency, p.is_verified
  from auth.users u
  join public.profiles p on p.id = u.id
 where lower(u.email) = 'ceo.arh.tech@gmail.com';

-- ============================================================================
-- FIM. Se a etapa [C] mostrou zeros, o ambiente foi revertido por completo.
-- ============================================================================
