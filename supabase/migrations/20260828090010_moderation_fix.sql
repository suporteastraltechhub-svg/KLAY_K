-- ============================================================================
-- Fix: grants estritos das RPCs de moderação (anon não deve invocar).
-- Por padrão o runner concede EXECUTE a anon/authenticated; revogamos de anon.
-- ============================================================================

revoke execute on function public.mod_list_reports(text) from public, anon;
revoke execute on function public.mod_update_report(uuid, text, text) from public, anon;
revoke execute on function public.mod_add_spam_rule(text, text, text) from public, anon;
revoke execute on function public.mod_remove_spam_rule(uuid) from public, anon;
revoke execute on function public.mod_list_spam_rules() from public, anon;
revoke execute on function public.mod_toggle_spam_rule(uuid, boolean) from public, anon;

revoke execute on function public.live_mod_ban(uuid, uuid, text) from public, anon;
revoke execute on function public.live_mod_unban(uuid, uuid) from public, anon;
revoke execute on function public.live_mod_mute(uuid, uuid, int, text) from public, anon;
revoke execute on function public.live_mod_unmute(uuid, uuid) from public, anon;
revoke execute on function public.can_moderate_live(uuid) from public, anon;