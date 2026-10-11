-- KLAY K · testes de segurança do Marketplace e dos Controles Familiares
--
-- NÃO EXECUTAR CONTRA PRODUÇÃO. Tudo roda dentro de uma transação que dá
-- ROLLBACK, então nada persiste.
--
--   psql "$DEV_DATABASE_URL" -v ON_ERROR_STOP=1 \
--        -f supabase/tests/marketplace_family_rls_test.sql
--
-- Cenários:
--   1. Vendedor não cria produto em nome de outro
--   2. Terceiro não edita nem apaga produto alheio
--   3. Produto pausado some do catálogo público
--   4. Comprador vê o pedido; terceiro não
--   5. Vendedor não marca pagamento como pago
--   6. Status do pedido respeita as transições
--   7. Estoque e preço vêm do servidor no checkout
--   8. Limite de tempo: só responsável ativo escreve
--   9. Relatório de atividade: responsável de terceiro é barrado
--  10. Aprovação de seguidor respeita require_follow_approval

begin;

create temporary table _r (cenario text, ok boolean, detalhe text default '') on commit drop;

create or replace function pg_temp._t(c text, ok boolean, d text default '')
returns void language plpgsql security definer as $$
begin
  insert into _r values (c, ok, d);
  raise notice '%  %  %', rpad(c, 52, '.'), case when ok then 'PASS' else 'FALHOU' end, d;
end $$;

-- Fixtures: 3 usuários reais (o trigger cria o profile sozinho)
create temporary table _u (vendedor uuid, comprador uuid, terceiro uuid, prod uuid) on commit drop;

-- Os blocos de teste trocam de papel (`set local role authenticated`) e
-- precisam ler os ids DEPOIS da troca. Sem este grant, o papel autenticado
-- recebe "permission denied for table _u".
grant select, insert, update on _u to authenticated, anon;

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, aud, role)
select gen_random_uuid(),
       format('mk-%s@klayk.test', v.nome),
       crypt('x', gen_salt('bf')),
       now(),
       '{"provider":"email"}'::jsonb,
       'authenticated',
       'authenticated'
  from (values ('vendedor'), ('comprador'), ('terceiro')) as v(nome);

insert into _u (vendedor, comprador, terceiro)
select
  (select id from auth.users where email = 'mk-vendedor@klayk.test'),
  (select id from auth.users where email = 'mk-comprador@klayk.test'),
  (select id from auth.users where email = 'mk-terceiro@klayk.test');

insert into public.store_products (id, seller_id, title, price, stock, status, image_url)
select gen_random_uuid(), v.vendedor, 'tenis usado', 150.00, 3, 'publicado', 'https://x/1.jpg'
from _u v;

update _u set prod = (select id from public.store_products where seller_id = _u.vendedor limit 1);

-- Um segundo produto, que NÃO é pausado em nenhum cenário, e um pedido real.
-- Sem o pedido, os testes de pagamento seriam vazios: o UPDATE afetaria zero
-- linhas, não levantaria erro, e "passaria" sem provar nada.
create temporary table _x (prod_ativo uuid, pedido uuid) on commit drop;
grant select, insert, update on _x to authenticated, anon;

insert into public.store_products (id, seller_id, title, price, stock, status, image_url)
select gen_random_uuid(), v.vendedor, 'camisa nova', 80.00, 10, 'publicado', 'https://x/2.jpg'
from _u v;

insert into _x (prod_ativo)
select id from public.store_products
 where seller_id = (select vendedor from _u) and title = 'camisa nova';

insert into public.store_orders (id, user_id, seller_id, total, status,
                                 shipping_name, shipping_phone, shipping_address)
select gen_random_uuid(), v.comprador, v.vendedor, 80.00, 'pendente',
       'Comprador Teste', '11999999999', 'Rua X, 1'
from _u v;

update _x set pedido = (select o.id from store_orders o
                        where o.shipping_name = 'Comprador Teste' limit 1);

-- helper: roda um bloco como um papel/usuário
create or replace function pg_temp._as(p_role text, p_uid uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '{"role":"anon","iss":"supabase"}'
         else '{"role":"' || p_role || '","sub":"' || p_uid::text || '","iss":"supabase"}' end,
    true);
  if p_role = 'anon' then execute 'set local role anon';
  else execute 'set local role ' || quote_ident(p_role); end if;
  execute p_sql;
  reset role;
end $$;

-- 1) Vendedor não cria produto em nome de outro ---------------------------
do $$
declare n integer; r record;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select terceiro from _u)::text || '","iss":"supabase"}', true);
  begin
    insert into public.store_products (seller_id, title, price, stock)
    values ((select vendedor from _u), 'produto plantado', 10, 1);
    perform pg_temp._t('1 nao cria produto em nome de outro', false, 'CONSEGUIU plantar vendedor');
  exception when insufficient_privilege then
    perform pg_temp._t('1 nao cria produto em nome de outro', true, 'WITH CHECK bloqueou');
  end;
  reset role;
end $$;

-- 2) Terceiro não edita nem apaga ------------------------------------------
do $$
declare n integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select terceiro from _u)::text || '","iss":"supabase"}', true);
  update public.store_products set title = 'invadido' where id = (select prod from _u);
  delete from public.store_products where id = (select prod from _u);
  reset role;

  select count(*) into n from public.store_products where title = 'invadido';
  perform pg_temp._t('2 terceiro nao edita nem apaga', n = 0,
                     case when n = 0 then 'nenhuma linha afetada'
                          else 'ALTEROU produto alheio' end);
end $$;

-- 3) Produto pausado some do catalogo, mas o dono continua vendo ----------
do $$
declare n integer; status_v text;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select vendedor from _u)::text || '","iss":"supabase"}', true);
  update public.store_products set status = 'pausado', is_active = false where id = (select prod from _u);
  reset role;

  set local role anon;
  perform set_config('request.jwt.claims', '{"role":"anon","iss":"supabase"}', true);
  select count(*) into n from public.store_products where id = (select prod from _u);
  reset role;

  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select vendedor from _u)::text || '","iss":"supabase"}', true);
  select count(*) into n from public.store_products where id = (select prod from _u);
  reset role;

  perform pg_temp._t('3 pausado: anon nao ve, dono ve', n = 1, 'dono ve ' || n);
end $$;

-- 5) NINGUEM dos dois marca pagamento como pago -----------------------------
--
-- Julga pelo ESTADO, não pela exceção. A RLS do comprador bloqueia a linha em
-- silêncio (UPDATE afeta 0 linhas, sem erro), enquanto o vendedor chega a
-- executar o UPDATE e é o trigger que levanta. "Não levantou erro" não prova
-- nada nos dois casos; o que prova é o valor da coluna depois.
do $$
declare v text;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select vendedor from _u)::text || '","iss":"supabase"}', true);
  begin
    update public.store_orders set payment_status = 'pago'
     where id = (select pedido from _x);
  exception when others then
    null;
  end;
  reset role;

  select payment_status into v from store_orders where id = (select pedido from _x);
  perform pg_temp._t('5 vendedor nao marca pagamento pago',
                     v = 'aguardando_pagamento', 'payment_status=' || v);

  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select comprador from _u)::text || '","iss":"supabase"}', true);
  begin
    update public.store_orders set payment_status = 'pago'
     where id = (select pedido from _x);
  exception when others then
    null;
  end;
  reset role;

  select payment_status into v from store_orders where id = (select pedido from _x);
  perform pg_temp._t('5b comprador nao marca pagamento pago',
                     v = 'aguardando_pagamento', 'payment_status=' || v);
end $$;

-- 6) Transicao de status invalida ------------------------------------------
do $$
begin
  if public.store_order_transition_ok('pendente', 'entregue') then
    perform pg_temp._t('6 pendente -> entregue bloqueado', false, 'permitiu pular etapa');
  else
    perform pg_temp._t('6 pendente -> entregue bloqueado', true, 'bloqueado');
  end if;

  if public.store_order_transition_ok('pendente', 'confirmado') then
    perform pg_temp._t('6b pendente -> confirmado permitido', true);
  else
    perform pg_temp._t('6b pendente -> confirmado permitido', false, 'bloqueou valida');
  end if;

  if public.store_order_transition_ok('entregue', 'cancelado') then
    perform pg_temp._t('6c entregue -> cancelado bloqueado', false, 'permitiu');
  else
    perform pg_temp._t('6c entregue -> cancelado bloqueado', true);
  end if;
end $$;

-- 8) Limite de tempo: responsavel exige vinculo ativo ----------------------
do $$
declare n integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select terceiro from _u)::text || '","iss":"supabase"}', true);
  begin
    perform public.family_set_time_limit((select comprador from _u), 60);
    perform pg_temp._t('8 terceiro nao define limite de tempo', false, 'CONSEGUIU');
  exception when others then
    perform pg_temp._t('8 terceiro nao define limite de tempo', true,
                       'erro=' || sqlerrm);
  end;
  reset role;

  -- agora com vinculo ativo
  insert into public.family_links (guardian_id, member_id, relationship, status, can_manage_safety)
  select terceiro, comprador, 'responsavel', 'active', true from _u;

  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select terceiro from _u)::text || '","iss":"supabase"}', true);
  perform public.family_set_time_limit((select comprador from _u), 90);
  reset role;

  select count(*) into n from public.family_time_limits
   where guardian_id = (select terceiro from _u) and daily_minutes = 90;
  perform pg_temp._t('8b responsavel ativo define limite', n = 1, 'linhas=' || n);
end $$;

-- 9) Relatorio: responsavel de terceiro barrado ----------------------------
do $$
declare j jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select comprador from _u)::text || '","iss":"supabase"}', true);
  begin
    j := public.family_activity_report((select vendedor from _u), 7);
    perform pg_temp._t('9 nao le relatorio de terceiro', false, 'CONSEGUIU ler');
  exception when others then
    perform pg_temp._t('9 nao le relatorio de terceiro', true, 'erro=' || sqlerrm);
  end;
  reset role;
end $$;

-- 9b) Responsavel ativo le o relatorio -------------------------------------
do $$
declare j jsonb; tem boolean;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select terceiro from _u)::text || '","iss":"supabase"}', true);
  j := public.family_activity_report((select comprador from _u), 7);
  reset role;

  tem := j ? 'posts' and j ? 'comments' and j ? 'minutes_used_today'
            and j ? 'pending_follow_requests';
  perform pg_temp._t('9b responsavel ativo le relatorio', tem,
                     case when tem then 'campos presentes'
                         else 'faltaram campos' end);
end $$;

-- 10) Follow com aprovacao -------------------------------------------------
do $$
declare j jsonb; seg uuid; n integer;
begin
  -- O DONO liga a exigência no próprio perfil. (Tentar isso em nome de outro é
  -- barrado pela RLS de profiles — e o teste abaixo 10z confirma isso.)
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select vendedor from _u)::text || '","iss":"supabase"}', true);
  update public.profiles set require_follow_approval = true where id = (select vendedor from _u);
  reset role;

  -- agora o solicitante pede
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select comprador from _u)::text || '","iss":"supabase"}', true);
  j := public.request_follow((select vendedor from _u));
  reset role;

  perform pg_temp._t('10 pedido criado quando alvo exige aprovacao',
                     j->>'requer_aprovacao' = 'true',
                     'status=' || coalesce(j->>'status','?'));

  select count(*) into n from public.follows
   where follower_id = (select comprador from _u) and following_id = (select vendedor from _u);
  perform pg_temp._t('10b ainda NAO virou follow direto', n = 0, 'follows=' || n);

  -- dono aprova
  select id into seg from public.follow_requests
   where follower_id = (select comprador from _u) limit 1;

  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select vendedor from _u)::text || '","iss":"supabase"}', true);
  j := public.respond_follow_request(seg, true);
  reset role;

  select count(*) into n from public.follows
   where follower_id = (select comprador from _u) and following_id = (select vendedor from _u);
  perform pg_temp._t('10c aprovacao materializa o follow', n = 1, 'follows=' || n);
end $$;

-- 10z) Nao se liga a exigencia de outro -------------------------------------
do $$
declare n integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select comprador from _u)::text || '","iss":"supabase"}', true);
  update public.profiles set require_follow_approval = true where id = (select vendedor from _u);
  reset role;

  select count(*) into n from public.profiles
   where id = (select vendedor from _u) and require_follow_approval = true;
  perform pg_temp._t('10z nao altera exigencia de outro', n = 1,
                     case when n = 1 then 'continua true (inalterado)' else 'ALTEROU' end);
end $$;

-- 10d) Sem exigencia: follow direto, sem pendencia -------------------------
do $$
declare j jsonb; n integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select terceiro from _u)::text || '","iss":"supabase"}', true);
  update public.profiles set require_follow_approval = false where id = (select comprador from _u);
  j := public.request_follow((select comprador from _u));
  reset role;

  perform pg_temp._t('10d sem exigencia: follow direto',
                     j->>'status' = 'seguindo', 'status=' || coalesce(j->>'status','?'));

  select count(*) into n from public.follow_requests
   where follower_id = (select terceiro from _u);
  perform pg_temp._t('10e sem exigencia: nao cria pedido', n = 0, 'pedidos=' || n);
end $$;

-- 11) Estoque insuficiente barrado pelo servidor ---------------------------
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || (select comprador from _u)::text || '","iss":"supabase"}', true);
  insert into public.store_cart_items (user_id, product_id, quantity)
  values ((select comprador from _u), (select prod_ativo from _x), 99);
  begin
    perform public.checkout_cart('Teste', '11999999999', 'Rua X, 1');
    perform pg_temp._t('11 estoque insuficiente barrado', false, 'checkout passou com 99 de estoque 3');
  exception when others then
    perform pg_temp._t('11 estoque insuficiente barrado', true,
                       left(sqlerrm, 40));
  end;
  delete from public.store_cart_items where user_id = (select comprador from _u);
  reset role;
end $$;

\echo ''
\echo '============ RESULTADO ============'
select cenario, ok, detalhe from _r order by ok, cenario;
\echo ''
\echo 'Esperado: todos ok = true.'

rollback;