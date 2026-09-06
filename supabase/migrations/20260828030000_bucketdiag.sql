-- Diagnóstico/criação de buckets de Storage (idempotente).
insert into storage.buckets (id, name, public) values
  ('avatars', 'avatars', true),
  ('covers', 'covers', true),
  ('videos', 'videos', false)
on conflict (id) do nothing;
