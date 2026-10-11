-- KLAY K · endurecimento de `share_events` + limpeza automática
--
-- ---------------------------------------------------------------------------
-- 1) POR QUE REVOGAR OS GRANTS
-- ---------------------------------------------------------------------------
-- A tabela nasceu com o GRANT padrão do Supabase (`anon` e `authenticated`
-- com os 7 privilégios de tabela). Ela está protegida pela RLS — ON e com ZERO
-- policies, o que nega tudo, e o PostgREST confirma devolvendo `[]`.
--
-- Ainda assim, dois motivos para revogar:
--
--   * `TRUNCATE` NÃO é governado por RLS. Se alguém desligar a RLS desta
--     tabela (um `alter table ... disable row level security` acidental), o
--     GRANT continua valendo e o atacante apaga o histórico inteiro de
--     `share_events` — o que zera o teto anti-abuso de 1/hora.
--   * `REFERENCE` e `TRIGGER` também não têm efeito protetor útil aqui.
--
-- Quem precisa ler a tabela? Ninguém. Quem precisa escrever? Só
-- `increment_post_share`, que é `security definer` e roda com os privilégios
-- do dono da tabela. Logo, revogar para anon/authenticated não quebra nada.
--
-- A tabela continua sendo referenciável por chave estrangeira e pelo dono.

revoke all on table public.share_events from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) ÍNDICE PARA A LIMPEZA
-- ---------------------------------------------------------------------------
-- A query de limpeza é `delete ... where created_at < now() - interval '24 hours'`.
-- O índice existente (`share_events_hour_idx`) é por (post_id, user_id,
-- created_at) e serve para a consulta do TETO, não para a limpeza. Este serve
-- para a limpeza.

create index if not exists share_events_created_at_idx
  on public.share_events (created_at);

-- ---------------------------------------------------------------------------
-- 3) LIMPEZA AUTOMÁTICA COM pg_cron
-- ---------------------------------------------------------------------------
-- `prune_share_events()` foi criada em 20261012120000 e é `security definer`,
-- com `EXECUTE` revogado de anon/authenticated. Ela nunca era chamada — sem
-- agendamento, `share_events` só cresceria.
--
-- pg_cron no Supabase está DISPONÍVEL e não instalado; `cron.database_name` é
-- `postgres`. O job roda como dono do banco, então a revogação acima não o
-- impede de chamar a função.
--
-- Ambos os blocos são idempotentes e toleram falha: se a extensão não puder
-- ser instalada (ambiente sem permissão, ou um Supabase self-hosted sem
-- pg_cron), a migration NÃO aborta — ela registra um aviso e segue. O
-- `prune_share_events()` continua disponível para chamada manual.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and not exists (select 1 from pg_extension where extname = 'pg_cron')
  then
    create extension pg_cron;
  end if;
exception when others then
  raise notice 'pg_cron nao pode ser instalado neste ambiente: %', sqlerrm;
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and not exists (select 1 from cron.job where jobname = 'prune-share-events')
  then
    -- A cada 30 minutos. A janela do teto é de 1 hora, então limpar com
    -- folga de 24h nunca derruba o registro que a taxa ainda consulta.
    perform cron.schedule(
      'prune-share-events',
      '*/30 * * * *',
      'select public.prune_share_events()'
    );
  end if;
exception when others then
  raise notice 'agendamento do prune-share-events falhou: %', sqlerrm;
end $$;
