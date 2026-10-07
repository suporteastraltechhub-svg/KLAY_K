-- KLAY K · Notificações — categorias que faltavam.
--
-- Complementa 20260831140000_growth.sql (tabela notification_preferences +
-- RPCs my_notification_prefs / save_notification_prefs).
--
-- Situação real que esta migration corrige
-- --------------------------------------
-- A tabela tem 8 colunas: likes, comments, follows, messages, live, missions,
-- rewards, push_enabled.
--
-- A edge function `send-push` filtra assim (linhas ~283-291):
--     case "like":                          allowed = p.likes
--     case "comment"/"comment_reply"/        allowed = p.comments
--          "mention"/"share":
--     case "follow":                         allowed = p.follows
--     case "message":                        allowed = p.messages
--     case "live":                           allowed = p.live
--     default:                               allowed = true
--
-- Três consequências:
--   1. "Respostas" (comment_reply) e "Menções" (mention) NÃO são independentes
--      — o usuário não consegue desligar só menções sem desligar comentários.
--   2. "Presentes" (gift) cai no `default`: **sempre enviado**, sem consultar
--      a preferência. O usuário não consegue desligar.
--   3. "Novidades do KLAY K" não existe como tipo no backend.
--
-- Esta migration adiciona 4 colunas. Nada é removido: as colunas antigas
-- continuam válidas e as RPCs existentes continuam funcionando. Quem aplicado
-- `push_enabled_default` (20260924000000) mantém o default true.

alter table public.notification_preferences
  add column if not exists replies boolean not null default true,
  add column if not exists mentions boolean not null default true,
  add column if not exists gifts boolean not null default true,
  add column if not exists news boolean not null default true;

comment on column public.notification_preferences.replies is
  'Notificações de resposta a comentário (tipo comment_reply).';
comment on column public.notification_preferences.mentions is
  'Notificações de menção (tipo mention).';
comment on column public.notification_preferences.gifts is
  'Notificações de presentes (tipos gift/gift_send/gift_sent).';
comment on column public.notification_preferences.news is
  'Novidades e comunicados do KLAY K.';

-- ---------------------------------------------------------------------------
-- As RPCs precisam devolver e aceitar as colunas novas.
-- O tipo de retorno muda (jsonb), então `create or replace` funciona, mas a
-- assinatura interna precisa casar com o que o Dart envia.
-- ---------------------------------------------------------------------------

create or replace function public.my_notification_prefs()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
  v public.notification_preferences;
begin
  if u is null then raise exception 'not_authenticated'; end if;
  insert into public.notification_preferences (user_id) values (u)
    on conflict (user_id) do nothing;
  select * into v from public.notification_preferences where user_id = u;
  -- As 8 chaves antigas seguem exatamente como antes (compatibilidade).
  -- As 4 novas são acrescentadas ao final.
  return jsonb_build_object(
    'likes', v.likes,
    'comments', v.comments,
    'follows', v.follows,
    'messages', v.messages,
    'live', v.live,
    'missions', v.missions,
    'rewards', v.rewards,
    'push_enabled', v.push_enabled,
    'replies', v.replies,
    'mentions', v.mentions,
    'gifts', v.gifts,
    'news', v.news
  );
end;
$$;
revoke all on function public.my_notification_prefs() from public;
grant execute on function public.my_notification_prefs() to authenticated;

-- `CREATE OR REPLACE` não aceita mudar a lista de argumentos. O DROP é seguro
-- porque a função só é chamada pelo app autenticado e é recriada logo abaixo.
drop function if exists public.save_notification_prefs(
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean
);
create or replace function public.save_notification_prefs(
  p_likes boolean default null,
  p_comments boolean default null,
  p_follows boolean default null,
  p_messages boolean default null,
  p_live boolean default null,
  p_missions boolean default null,
  p_rewards boolean default null,
  p_push_enabled boolean default null,
  p_replies boolean default null,
  p_mentions boolean default null,
  p_gifts boolean default null,
  p_news boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid := auth.uid();
begin
  if u is null then raise exception 'not_authenticated'; end if;
  insert into public.notification_preferences (user_id) values (u)
    on conflict (user_id) do nothing;
  update public.notification_preferences set
    likes = coalesce(p_likes, likes),
    comments = coalesce(p_comments, comments),
    follows = coalesce(p_follows, follows),
    messages = coalesce(p_messages, messages),
    live = coalesce(p_live, live),
    missions = coalesce(p_missions, missions),
    rewards = coalesce(p_rewards, rewards),
    push_enabled = coalesce(p_push_enabled, push_enabled),
    replies = coalesce(p_replies, replies),
    mentions = coalesce(p_mentions, mentions),
    gifts = coalesce(p_gifts, gifts),
    news = coalesce(p_news, news),
    updated_at = now()
   where user_id = u;
  return public.my_notification_prefs();
end;
$$;
revoke all on function public.save_notification_prefs(
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean,
  boolean, boolean, boolean, boolean
) from public;
grant execute on function public.save_notification_prefs(
  boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean,
  boolean, boolean, boolean, boolean
) to authenticated;

-- ---------------------------------------------------------------------------
-- Filtro de permissão: uma única fonte de verdade, reutilizável.
-- A edge function `send-push` passa a chamar isto em vez do switch solto, para
-- que "ligar/desligar Presentes" realmente pare de entregar push de gift.
-- ---------------------------------------------------------------------------

create or replace function public.notification_allowed(
  p_user_id uuid,
  p_type text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  p public.notification_preferences;
begin
  if p_user_id is null then return false; end if;

  select * into p from public.notification_preferences
   where user_id = p_user_id;
  -- Sem linha = usuário ainda não abriu a tela de prefs: envia (mesmo
  -- comportamento do `if (prefs)` em JS, que só filtra quando a linha existe).
  if p.user_id is null then return true; end if;

  if p.push_enabled = false then return false; end if;

  -- Cada tipo consulta SUA coluna; as antigas continuam válidas.
  return case p_type
    when 'like'                        then p.likes
    -- 'comment' e 'share' seguem como antes; 'mention' e 'comment_reply'
    -- agora são independentes, que é o ponto desta migration.
    when 'comment'                     then p.comments
    when 'share'                       then p.comments
    when 'mention'                     then p.mentions
    when 'comment_reply'               then p.replies
    when 'follow'                      then p.follows
    when 'message'                     then p.messages
    when 'live'                        then p.live
    when 'gift'                        then p.gifts
    when 'gift_send'                   then p.gifts
    when 'gift_sent'                   then p.gifts
    when 'news'                        then p.news
    -- 'missions'/'rewards' já eram treatados como_notificações in-app e
    -- não chegam por push; mantidos aqui para completude.
    when 'missions'                    then p.missions
    when 'rewards'                     then p.rewards
    else true
  end;
end;
$$;
revoke all on function public.notification_allowed(uuid, text) from public;
grant execute on function public.notification_allowed(uuid, text) to authenticated;
grant execute on function public.notification_allowed(uuid, text) to service_role;