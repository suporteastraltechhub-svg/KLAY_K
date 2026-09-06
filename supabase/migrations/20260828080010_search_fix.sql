-- ============================================================================
-- Fix: grants restritos das funções de busca (anon não deve EXECUTE).
-- ============================================================================

revoke execute on function public.record_search(text, text) from public, anon;
grant execute on function public.record_search(text, text) to authenticated;

revoke execute on function public.clear_search_history() from public, anon;
grant execute on function public.clear_search_history() to authenticated;