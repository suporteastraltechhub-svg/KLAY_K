-- ============================================================================
-- KLAY K — PAGAMENTO DE PRESENTES ATÔMICO (correção raiz)
--
-- ANTES: a Edge Function `send-gift` fazia débito, inserção da transação,
-- live_gifts/live_chat/live_events/notificações e stats em VÁRIOS passos
-- independentes. Um passo podia falhar e os demais "passavam batido":
--   * se `gift_transactions.insert` falhasse, o débito já tinha acontecido,
--     o app recebia `ok:true` com `transaction_id:null` e o presente NÃO era
--     registrado (presente "bugado": moedas sumiram sem registro).
--   * `live_gifts`/`live_events` eram insert fire-and-forget (erro oculto).
--
-- AGORA: TODO o gasto é feito em UMA transação do Postgres pelo
-- `public.process_gift_spend` (security definer, somente service_role):
-- débito + transactions + feed da live + evento + notificação + stats,
-- ou tudo acontece, ou nada (qualquer falha reverte o débito).
--
-- Não altera tabelas existentes nem RLS: é apenas uma nova função (aditiva).
-- Deploy: aplicar esta migration e re-deployar `send-gift`.
-- ============================================================================

create or replace function public.process_gift_spend(
  p_request_id text,
  p_user_id uuid,
  p_gift_id text,
  p_gift_name text,
  p_gift_icon text,
  p_gift_animation text,
  p_rarity_id text,
  p_credits_per_unit bigint,
  p_amount int,
  p_live_id uuid,
  p_receiver_id uuid,
  p_sender_name text,
  p_unlimited boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance bigint;
  v_total bigint;
  v_tx_id uuid;
  v_spent bigint;
  v_chat text;
begin
  if p_user_id is null then raise exception 'not_authenticated'; end if;
  if p_amount <= 0 then raise exception 'invalid_amount'; end if;
  if p_live_id is not null and not exists (select 1 from public.lives where id = p_live_id) then
    raise exception 'live_not_found';
  end if;

  v_spent := 0;
  v_balance := coalesce(
    (select credits from public.user_wallets where user_id = p_user_id), 0
  );

  if not coalesce(p_unlimited, false) then
    v_total := p_credits_per_unit * p_amount;
    update public.user_wallets
       set credits = credits - v_total,
           updated_at = now()
     where user_id = p_user_id
       and credits >= v_total
     returning credits into v_balance;
    if v_balance is null then raise exception 'insufficient_credits'; end if;
    v_spent := v_total;
  end if;

  insert into public.gift_transactions (
    user_id, receiver_id, live_id, gift_id, gift_name,
    amount, credits_per_unit, credits_total, balance_after, request_id
  ) values (
    p_user_id, p_receiver_id, p_live_id, p_gift_id, p_gift_name,
    p_amount, p_credits_per_unit, v_spent, v_balance, p_request_id
  )
  returning id into v_tx_id;

  insert into public.credit_transactions (
    user_id, delta, balance_after, kind, ref_type, ref_id, note
  ) values (
    p_user_id,
    case when coalesce(p_unlimited, false) then 0 else -v_spent end,
    v_balance,
    'spend',
    'gift',
    p_gift_id || ':' || p_amount,
    'Envio de ' || p_gift_name || ' x' || p_amount
      || case when coalesce(p_unlimited, false) then ' (fundador ilimitado)' else '' end
  );

  if p_live_id is not null then
    v_chat := '🎁 ' || coalesce(nullif(p_sender_name, ''), 'Alguém')
      || ' enviou ' || p_gift_icon || ' ' || p_gift_name || ' x' || p_amount;

    insert into public.live_chat (live_id, user_id, message)
    values (p_live_id, p_user_id, v_chat);

    insert into public.live_gifts (
      live_id, sender_id, receiver_id, gift_id, gift_name, gift_amount
    ) values (
      p_live_id, p_user_id, p_receiver_id, p_gift_id, p_gift_name, p_amount
    );

    insert into public.live_events (
      live_id, event_type, user_id, username, metadata
    ) values (
      p_live_id, 'GIFT_RECEIVED', p_user_id, p_sender_name,
      jsonb_build_object(
        'gift_id', p_gift_id,
        'gift_name', p_gift_name,
        'gift_icon', p_gift_icon,
        'gift_amount', p_amount,
        'gift_animation', p_gift_animation,
        'rarity_id', p_rarity_id,
        'message', v_chat
      )
    );

    if p_receiver_id is not null then
      insert into public.notifications (
        user_id, actor_id, type, ref_id, message
      ) values (
        p_receiver_id, p_user_id, 'gift', v_tx_id::text,
        coalesce(nullif(p_sender_name, ''), 'Alguém') || ' enviou '
          || p_gift_icon || ' ' || p_gift_name || ' x' || p_amount
      );
    end if;
  end if;

  -- Incremento atômico dos stats (ON CONFLICT — sem race de read-modify-write).
  perform public.increment_gift_stats(p_gift_id, p_amount, 0);

  return jsonb_build_object(
    'ok', true,
    'transaction_id', v_tx_id,
    'amount', p_amount,
    'credits_spent', v_spent,
    'balance', v_balance,
    'unlimited', coalesce(p_unlimited, false)
  );
end;
$$;

revoke all on function public.process_gift_spend(text, uuid, text, text, text, text, text, bigint, int, uuid, uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.process_gift_spend(text, uuid, text, text, text, text, text, bigint, int, uuid, uuid, text, boolean) to service_role;