-- ============================================================================
-- Realtime das notificações: habilita `notifications` na publicação
-- supabase_realtime para entregar inserts (curtidas, comentários, seguidores,
-- vendas na loja etc.) ao app em tempo real. A RLS (dono) filtra os eventos.
-- ============================================================================

alter publication supabase_realtime add table public.notifications;