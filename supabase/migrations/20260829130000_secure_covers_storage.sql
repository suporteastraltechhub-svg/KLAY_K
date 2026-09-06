-- Segurança do storage de capas.
--
-- O bucket `covers` servia com a política antiga `covers_public` (`for all`),
-- que permitia QUALQUER usuário escrever em QUALQUER caminho da pasta —
-- inclusive sobrepor capas de outros criadores (posts e lives compartilham o
-- bucket). Agora a LEITURA continua pública (capas são assets públicos), mas a
-- escrita é restrita ao DONO do objeto (primeira pasta do caminho == auth.uid()),
-- espelhando o que já existe para o bucket privado `videos`.
--
-- Atenção: o Flutter sempre sobe em `{uid}/{timestamp}.{ext}`, então a
-- condição `(storage.foldername(name))[1] = auth.uid()::text` casa com o
-- upload legítimo do app.

drop policy if exists "covers_public" on storage.objects;

create policy "covers_select_public" on storage.objects
  for select using (bucket_id = 'covers');

create policy "covers_insert_owner" on storage.objects
  for insert with check (
    bucket_id = 'covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "covers_update_owner" on storage.objects
  for update using (
    bucket_id = 'covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  ) with check (
    bucket_id = 'covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "covers_delete_owner" on storage.objects
  for delete using (
    bucket_id = 'covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );