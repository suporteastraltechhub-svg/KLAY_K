-- ============================================================================
-- KLAY K — Config Globais (Painel do Fundador) + Ferramentas de Rei
-- ============================================================================
-- 1) `app_config`: chave/valor global lido em runtime pelo app. Nenhum acesso
--    direto à tabela (RLS fecha tudo); só via RPCs `security definer` com caps
--    (roles/settings) e auditoria em cada alteração.
-- 2) Ferramentas de Rei reutilizam o motor anti-hack do Guardian existente
--    (guardian_list_rules/guardian_toggle_rule/guardian_run_rules/
--    guardian_list_alerts/guardian_resolve_alert) — nada novo a migrar.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) app_config
-- ---------------------------------------------------------------------------
create table if not exists public.app_config (
  key text primary key,
  value jsonb not null default 'null',
  description text not null default '',
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint app_config_key_format check (
    char_length(key) between 2 and 64
    and key ~ '^[A-Za-z0-9._-]+$'
  )
);

-- Defaults documentados (inertes até o app passar a lê-los); nunca sobrescrevem.
insert into public.app_config (key, value, description) values
  ('economy.gift_spend_multiplier', '1.0', 'Multiplicador de gasto em presentes (padrão 1.0).'),
  ('economy.chest_cost_multiplier', '1.0', 'Multiplicador de custo de baús (padrão 1.0).'),
  ('growth.xp_multiplier', '1.0', 'Multiplicador de XP de comunidade/missões (padrão 1.0).')
on conflict (key) do nothing;

alter table public.app_config enable row level security;
drop policy if exists "app_config_none" on public.app_config;
create policy "app_config_none" on public.app_config
  for select using (false);
revoke all on table public.app_config from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) founder_get_config(): retorna todas as chaves (cap roles/settings)
-- ---------------------------------------------------------------------------
create or replace function public.founder_get_config()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not (public.has_perm('roles') or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  select jsonb_object_agg(
    c.key,
    jsonb_build_object(
      'value', c.value,
      'description', coalesce(c.description, ''),
      'updated_at', c.updated_at
    )
  ) into v
  from public.app_config c;
  return coalesce(v, '{}'::jsonb);
end;
$$;

revoke all on function public.founder_get_config() from public;
revoke execute on function public.founder_get_config() from anon, authenticated;
grant execute on function public.founder_get_config() to authenticated;

-- ---------------------------------------------------------------------------
-- 3) founder_set_config(): cria/atualiza chave (cap roles/settings; audita)
-- ---------------------------------------------------------------------------
create or replace function public.founder_set_config(
  p_key text,
  p_value jsonb,
  p_description text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_desc text;
begin
  if not (public.has_perm('roles') or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  v_key := btrim(coalesce(p_key, ''));
  v_desc := btrim(coalesce(p_description, ''));
  if char_length(v_key) < 2 or char_length(v_key) > 64
     or v_key !~ '^[A-Za-z0-9._-]+$' then
    raise exception 'bad_key';
  end if;
  if p_value is null then
    raise exception 'bad_value';
  end if;

  insert into public.app_config (key, value, description, updated_by, updated_at)
  values (v_key, p_value, v_desc, auth.uid(), now())
  on conflict (key) do update
    set value = excluded.value,
        description = excluded.description,
        updated_by = excluded.updated_by,
        updated_at = now();

  perform public.write_audit('config.set', 'config', v_key,
    jsonb_build_object('value', p_value));
  return jsonb_build_object('ok', true, 'key', v_key);
end;
$$;

revoke all on function public.founder_set_config(text, jsonb, text) from public;
revoke execute on function public.founder_set_config(text, jsonb, text) from anon, authenticated;
grant execute on function public.founder_set_config(text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) founder_delete_config(): remove chave (cap roles/settings; audita)
-- ---------------------------------------------------------------------------
create or replace function public.founder_delete_config(
  p_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.has_perm('roles') or public.has_perm('settings')) then
    raise exception 'not_admin';
  end if;
  delete from public.app_config where key = btrim(p_key);
  if not found then raise exception 'not_found'; end if;
  perform public.write_audit('config.delete', 'config', btrim(p_key), '{}'::jsonb);
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.founder_delete_config(text) from public;
revoke execute on function public.founder_delete_config(text) from anon, authenticated;
grant execute on function public.founder_delete_config(text) to authenticated;