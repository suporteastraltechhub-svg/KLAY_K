-- ============================================================================
-- KLAY K — RECOMPENSA POR CICLO ASSISTIDO (WATCH CYCLE)
--
-- Concede EXATAMENTE 15 moedas por ciclo válido, com cooldown de 20s, validado
-- EXCLUSIVAMENTE no backend (horário do servidor, auth.uid()). O cliente
-- apenas chama a RPC; jamais envia user_id, valor ou atualiza saldo.
--
-- Reutiliza o sistema de economia existente:
--   * user_wallets        (saldo 'credits')
--   * credit_transactions (ledger, kind = 'reward')
--   * economy_adjust(...) (RPC security definer — escrita de saldo)
-- Sem duplicar saldo/histórico.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Tabela de cooldown por usuário (1 linha por usuário).
-- ---------------------------------------------------------------------------
create table if not exists public.watch_cycle_rewards (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_claim_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.watch_cycle_rewards enable row level security;

-- O usuário pode VER a própria linha, mas NUNCA alterá-la manualmente.
drop policy if exists "watch_cycle_rewards_select_own"
  on public.watch_cycle_rewards;
create policy "watch_cycle_rewards_select_own"
  on public.watch_cycle_rewards for select
  using (user_id = auth.uid());

-- Sem policies de inserção/atualização/exclusão: apenas a RPC security
-- definer abaixo grava (como owner, ignora RLS). O cliente não pode forjar
-- last_claim_at nem créditos.

-- ---------------------------------------------------------------------------
-- RPC claim_watch_cycle_reward()
--   * Identifica o usuário via auth.uid() (nunca aceita parâmetros do cliente).
--   * Recompensa fixa de 15 moedas (credits).
--   * Cooldown mínimo de 20s medido com horário do servidor (now()).
--   * Trava de sessão (pg_advisory_xact_lock) contra chamadas simultâneas.
--   * Atualiza o saldo via economy_adjust() e registra o ledger.
--   * Retorna { ok, reward, balance, next_available_at }.
-- ---------------------------------------------------------------------------
create or replace function public.claim_watch_cycle_reward()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v_reward constant bigint := 15;
  v_cooldown constant interval := interval '20 seconds';
  v_last timestamptz;
  v_next timestamptz;
  v_result jsonb;
  v_balance bigint;
  v_now timestamptz;
begin
  -- 1) Identifica o usuário automaticamente; recusa visitantes/não autenticados.
  if u is null then
    raise exception 'not_authenticated' using errcode = '22023';
  end if;

  -- 2) Trava de sessão: serializa chamadas concorrentes do mesmo usuário,
  --    impedindo que duas requisições paralelas concedam recompensa dupla.
  perform pg_advisory_xact_lock(hashtext('klayk_watch_reward:' || u::text));

  --    Horário do servidor capturado DENTRO da trava, para que o cooldown
  --    seja medido a partir do momento em que a requisição de fato venceu.
  v_now := now();

  -- 3) Reavalia o cooldown DENTRO da trava (fonte de verdade = servidor).
  select last_claim_at into v_last
    from public.watch_cycle_rewards
   where user_id = u;

  if v_last is not null and (v_now - v_last) < v_cooldown then
    v_next := v_last + v_cooldown;
    return jsonb_build_object(
      'ok', false,
      'reward', 0,
      'balance', coalesce(
        (select credits from public.user_wallets where user_id = u), 0),
      'next_available_at', v_next,
      'error', 'Recompensa ainda em cooldown.'
    );
  end if;

  -- 4) Concede exatamente a recompensa via sistema existente (saldo + ledger).
  v_result := public.economy_adjust(
    p_user_id => u,
    p_currency => 'credits',
    p_delta => v_reward,
    p_kind => 'reward',
    p_ref_type => 'watch_cycle',
    p_ref_id => '',
    p_note => 'Recompensa ciclo assistido',
    p_audit_action => null
  );
  v_balance := (v_result->>'balance')::bigint;

  -- 5) Marca o cooldown (upsert idempotente).
  insert into public.watch_cycle_rewards (user_id, last_claim_at, created_at)
  values (u, v_now, v_now)
  on conflict (user_id) do update
    set last_claim_at = excluded.last_claim_at;

  -- 6) Retorna o estado real (saldo vindo do servidor, nunca do cliente).
  return jsonb_build_object(
    'ok', true,
    'reward', v_reward,
    'balance', v_balance,
    'next_available_at', v_now + v_cooldown
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants: somente o usuário autenticado pode EXECUTAR a RPC; nada de update
-- direto em user_wallets / credit_transactions / watch_cycle_rewards.
-- ---------------------------------------------------------------------------
revoke all on function public.claim_watch_cycle_reward() from public;
grant execute on function public.claim_watch_cycle_reward() to authenticated;

-- Reforço: o cliente NUNCA deve ter permissão de escrita nas tabelas de saldo.
-- (economy_adjust já está revogado do cliente no migration de economia.)
revoke insert, update, delete on public.watch_cycle_rewards from anon, authenticated;
revoke insert, update, delete on public.user_wallets from anon, authenticated;
revoke insert, update, delete on public.credit_transactions from anon, authenticated;
