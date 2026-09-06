-- KLAY K — RASCUNHOS: idempotência real na publicação
-- `drafts.post_id`  -> post criado no feed (evita duplicar na republicação).
-- Idempotente; aplicada ao vivo via Management API (não usar `supabase db push`).
alter table public.drafts
  add column if not exists post_id uuid references public.posts(id) on delete set null;

create index if not exists drafts_post_user_idx
  on public.drafts (user_id, post_id) where post_id is not null;