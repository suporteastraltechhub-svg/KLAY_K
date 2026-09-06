-- KLAY K - RPCs financeiros do catálogo de presentes.
-- Implementados com security definer para garantir atomicidade; EXECUTE é
-- concedido apenas ao service_role (Edge Functions) — usuários anônimos não
-- conseguem debitar diretamente, impedindo desvio do fluxo de envio.

-- ---------------------------------------------------------------------------
-- debit_credits: debita créditos de forma atômica (só ao ter saldo suficiente).
-- Retorna o saldo após o débito, ou falha se não houver saldo.
-- ---------------------------------------------------------------------------
create or replace function public.debit_credits(
  p_user_id uuid,
  p_delta bigint
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance bigint;
begin
  if p_delta <= 0 then
    raise exception 'invalid_delta';
  end if;

  update public.user_wallets
     set credits = credits - p_delta,
         updated_at = now()
   where user_id = p_user_id
     and credits >= p_delta
   returning credits into v_balance;

  if v_balance is null then
    raise exception 'insufficient_credits';
  end if;

  return jsonb_build_object('balance', v_balance);
end;
$$;

revoke execute on function public.debit_credits(uuid, bigint) from public, anon, authenticated;
grant execute on function public.debit_credits(uuid, bigint) to service_role;

-- ---------------------------------------------------------------------------
-- increment_gift_stats: incrementa contadores de uso (chamado pelo backend).
-- ---------------------------------------------------------------------------
create or replace function public.increment_gift_stats(
  p_gift_id text,
  p_sent bigint default 0,
  p_received bigint default 0
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.gift_usage_stats (gift_id, sent_count, received_count, updated_at)
  values (p_gift_id, p_sent, p_received, now())
  on conflict (gift_id) do update set
    sent_count = public.gift_usage_stats.sent_count + excluded.sent_count,
    received_count = public.gift_usage_stats.received_count + excluded.received_count,
    last_sent_at = case when excluded.sent_count > 0 then now() else public.gift_usage_stats.last_sent_at end,
    last_received_at = case when excluded.received_count > 0 then now() else public.gift_usage_stats.last_received_at end,
    updated_at = now();
end;
$$;

revoke execute on function public.increment_gift_stats(text, bigint, bigint) from public, anon, authenticated;
grant execute on function public.increment_gift_stats(text, bigint, bigint) to service_role;
