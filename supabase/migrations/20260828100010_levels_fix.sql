-- ============================================================================
-- Fix: re-seed levels (se necessário), RLS de leitura no catálogo, e revoga
-- EXECUTE de anon/authenticated em funções destinadas a TRIGGERS do banco.
-- ============================================================================

-- Re-seed idempotente (garante os níveis mesmo que o insert anterior não
-- tenha persistido por qualquer razão).
insert into public.levels (level, xp_required, title) values
  (1, 0,    'Novato'),
  (2, 100,  'Explorador'),
  (3, 250,  'Criador'),
  (4, 500,  'Estrela em ascensão'),
  (5, 1000, 'Estrela K'),
  (6, 2000, 'Ícone'),
  (7, 4000, 'Lenda'),
  (8, 8000, 'Mito K'),
  (9, 16000,'Imortal'),
  (10, 32000,'Deus do KLAY K')
on conflict (level) do nothing;

-- Leitura pública do catálogo de níveis, igual às missions
alter table public.levels enable row level security;
drop policy if exists "levels_select" on public.levels;
create policy "levels_select" on public.levels for select using (true);

-- ---------------------------------------------------------------------------
-- Segurança: funções de premiação são chamadas SOMENTE por triggers do banco
-- (que rodam como owner). Remover EXECUTE de clientes evita escalada (anon
-- podia conceder progresso/XP com user_id arbitrário).
-- ---------------------------------------------------------------------------
revoke execute on function public.grant_mission_progress(uuid, text, int) from public, anon, authenticated;
revoke execute on function public.auto_unlock_achievements(uuid) from public, anon, authenticated;

-- my_progress: anon não deve nem invocar
revoke execute on function public.my_progress() from public, anon;