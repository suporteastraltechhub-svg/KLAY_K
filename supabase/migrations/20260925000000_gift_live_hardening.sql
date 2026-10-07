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
  v_request_id text := nullif(btrim(coalesce(p_request_id, '')), '');
  v_live public.lives%rowtype;
  v_gift public.gifts%rowtype;
  v_claim_user uuid;
  v_existing public.gift_transactions%rowtype;
  v_earnings jsonb;
  v_balance bigint;
  v_total bigint;
  v_tx_id uuid;
  v_spent bigint := 0;
  v_chat text;
  v_sender_name text := left(coalesce(nullif(btrim(p_sender_name), ''), 'Alguém'), 80);
  v_unlimited boolean;
begin
  if p_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 999 then
    raise exception 'invalid_amount';
  end if;
  if v_request_id is not null and (char_length(v_request_id) < 8 or char_length(v_request_id) > 64) then
    raise exception 'invalid_request_id';
  end if;
  if p_receiver_id is not null and p_receiver_id = p_user_id then
    raise exception 'cannot_send_to_self';
  end if;
  if p_live_id is not null and p_receiver_id is null then
    raise exception 'receiver_id_required';
  end if;

  if v_request_id is not null then
    select *
      into v_existing
      from public.gift_transactions
     where request_id = v_request_id
       and user_id = p_user_id;

    if found then
      select coalesce(
        (select founder_unlimited_currency from public.profiles where id = p_user_id),
        false
      ) into v_unlimited;

      if v_existing.receiver_id is not null and v_existing.credits_total > 0 then
        v_earnings := public.process_gift_earnings(
          v_existing.id,
          v_existing.receiver_id,
          v_existing.credits_total
        );
        if coalesce((v_earnings->>'ok')::boolean, false) is not true then
          raise exception 'gift_earnings_failed';
        end if;
      end if;

      return jsonb_build_object(
        'ok', true,
        'duplicate', true,
        'transaction_id', v_existing.id,
        'amount', v_existing.amount,
        'credits_spent', v_existing.credits_total,
        'balance', v_existing.balance_after,
        'unlimited', v_unlimited,
        'earnings_processed', true
      );
    end if;

    if exists (
      select 1
        from public.gift_transactions
       where request_id = v_request_id
    ) then
      raise exception 'request_id_conflict';
    end if;
  end if;

  if p_live_id is not null then
    select *
      into v_live
      from public.lives
     where id = p_live_id
     for share;

    if not found then
      raise exception 'live_not_found';
    end if;
    if v_live.status <> 'live' then
      raise exception 'live_not_active';
    end if;
    if v_live.streamer_id <> p_receiver_id then
      raise exception 'receiver_not_streamer';
    end if;
  end if;

  select *
    into v_gift
    from public.gifts
   where id = p_gift_id
   for share;

  if not found then
    raise exception 'gift_not_found';
  end if;
  if v_gift.status <> 'active' then
    raise exception 'gift_unavailable';
  end if;
  if v_gift.featured_start is not null and v_gift.featured_start > now() then
    raise exception 'gift_unavailable';
  end if;
  if v_gift.featured_end is not null and v_gift.featured_end < now() then
    raise exception 'gift_unavailable';
  end if;

  select coalesce(
    (select founder_unlimited_currency from public.profiles where id = p_user_id),
    false
  ) into v_unlimited;

  if v_request_id is not null then
    loop
      select user_id
        into v_claim_user
        from public.gift_requests
       where request_id = v_request_id
       for update;

      if v_claim_user is not null then
        if v_claim_user <> p_user_id then
          raise exception 'request_id_conflict';
        end if;

        select *
          into v_existing
          from public.gift_transactions
         where request_id = v_request_id
           and user_id = p_user_id;

        if found then
          if v_existing.receiver_id is not null and v_existing.credits_total > 0 then
            v_earnings := public.process_gift_earnings(
              v_existing.id,
              v_existing.receiver_id,
              v_existing.credits_total
            );
            if coalesce((v_earnings->>'ok')::boolean, false) is not true then
              raise exception 'gift_earnings_failed';
            end if;
          end if;

          return jsonb_build_object(
            'ok', true,
            'duplicate', true,
            'transaction_id', v_existing.id,
            'amount', v_existing.amount,
            'credits_spent', v_existing.credits_total,
            'balance', v_existing.balance_after,
            'unlimited', v_unlimited,
            'earnings_processed', true
          );
        end if;

        delete from public.gift_requests
         where request_id = v_request_id
           and user_id = p_user_id;
      end if;

      insert into public.gift_requests (request_id, user_id)
      values (v_request_id, p_user_id)
      on conflict (request_id) do nothing;

      if found then
        exit;
      end if;
    end loop;
  end if;

  insert into public.user_wallets (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  v_total := v_gift.credits * p_amount;
  select credits into v_balance
    from public.user_wallets
   where user_id = p_user_id;

  if not v_unlimited then
    update public.user_wallets
       set credits = credits - v_total,
           updated_at = now()
     where user_id = p_user_id
       and credits >= v_total
    returning credits into v_balance;
    if v_balance is null then
      raise exception 'insufficient_credits';
    end if;
    v_spent := v_total;
  end if;

  insert into public.gift_transactions (
    user_id, receiver_id, live_id, gift_id, gift_name,
    amount, credits_per_unit, credits_total, balance_after, request_id
  ) values (
    p_user_id, p_receiver_id, p_live_id, v_gift.id, v_gift.name,
    p_amount, v_gift.credits, v_spent, v_balance, v_request_id
  )
  returning id into v_tx_id;

  insert into public.credit_transactions (
    user_id, delta, balance_after, kind, ref_type, ref_id, note, currency
  ) values (
    p_user_id,
    case when v_unlimited then 0 else -v_spent end,
    v_balance,
    'spend',
    'gift',
    v_gift.id || ':' || p_amount,
    'Envio de ' || v_gift.name || ' x' || p_amount
      || case when v_unlimited then ' (fundador ilimitado)' else '' end,
    'credits'
  );

  if p_live_id is not null then
    v_chat := '🎁 ' || v_sender_name
      || ' enviou ' || v_gift.icon || ' ' || v_gift.name || ' x' || p_amount;

    insert into public.live_chat (live_id, user_id, message)
    values (p_live_id, p_user_id, v_chat);

    insert into public.live_gifts (
      live_id, sender_id, receiver_id, gift_id, gift_name, gift_amount
    ) values (
      p_live_id, p_user_id, p_receiver_id, v_gift.id, v_gift.name, p_amount
    );

    insert into public.live_events (
      live_id, event_type, user_id, username, metadata
    ) values (
      p_live_id, 'GIFT_RECEIVED', p_user_id, v_sender_name,
      jsonb_build_object(
        'gift_id', v_gift.id,
        'gift_name', v_gift.name,
        'gift_icon', v_gift.icon,
        'gift_amount', p_amount,
        'gift_animation', v_gift.animation_key,
        'rarity_id', v_gift.rarity_id,
        'message', v_chat
      )
    );

    insert into public.notifications (
      user_id, actor_id, type, ref_id, message
    ) values (
      p_receiver_id, p_user_id, 'gift', v_tx_id::text,
      v_sender_name || ' enviou ' || v_gift.icon || ' ' || v_gift.name || ' x' || p_amount
    );
  end if;

  if p_receiver_id is not null and v_spent > 0 then
    v_earnings := public.process_gift_earnings(
      v_tx_id,
      p_receiver_id,
      v_spent
    );
    if coalesce((v_earnings->>'ok')::boolean, false) is not true then
      raise exception 'gift_earnings_failed';
    end if;
  end if;

  perform public.increment_gift_stats(v_gift.id, p_amount, 0);

  return jsonb_build_object(
    'ok', true,
    'duplicate', false,
    'transaction_id', v_tx_id,
    'amount', p_amount,
    'credits_spent', v_spent,
    'balance', v_balance,
    'unlimited', v_unlimited,
    'earnings_processed', true
  );
end;
$$;

revoke all on function public.process_gift_spend(text, uuid, text, text, text, text, text, bigint, int, uuid, uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.process_gift_spend(text, uuid, text, text, text, text, text, bigint, int, uuid, uuid, text, boolean) to service_role;

notify pgrst, 'reload schema';
