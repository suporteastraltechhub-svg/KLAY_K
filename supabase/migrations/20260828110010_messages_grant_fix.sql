-- ============================================================================
-- Fix: fecha o execute de unread_message_count para public/anon.
-- A função é security definer e já retorna 0 para anon (auth.uid() nulo), mas o
-- padrão inicial do Supabase concede execute ao público; removemos para manter a
-- superfície consistente com as demais RPCs de mensagens.
-- ============================================================================

revoke execute on function public.unread_message_count() from public, anon;
grant execute on function public.unread_message_count() to authenticated;