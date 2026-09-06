-- KLAY K - Catálogo de presentes virtuais (escalável, 50k+ / 100k+).
--
-- Arquitetura:
--   * O catálogo vive no banco (colunas + seed). Novos presentes são criados
--     via painel administrativo (Edge Function gift-admin / service role),
--     sem precisar alterar o código do app nem o APK.
--   * Créditos/wallet e envio de presentes são SEMPRE validados no backend
--     (Edge Function send-gift com service role). O cliente jamais altera saldo.
--   * Tabelas existentes são REUTILIZADAS: a tabela `live_gifts` (presentes
--     recebidos na live, com realtime via live_events) e `live_events`/`live_chat`
--     continuam sendo os canais reais da transmissão. Aqui adicionamos apenas o
--     catálogo e o ledger financeiro que ainda não existiam.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- user_wallets: saldo de créditos (ledger fonte de verdade do saldo).
-- Só o service role (Edge Functions) altera o saldo. Usuário comum lê o próprio.
-- ---------------------------------------------------------------------------
create table if not exists public.user_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  credits bigint not null default 0 check (credits >= 0),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- credit_transactions: livro-caixa de movimentações de créditos.
-- Apenas inseridas pelo service role (grant/spend/refund).
-- ---------------------------------------------------------------------------
create table if not exists public.credit_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  delta bigint not null,
  balance_after bigint not null,
  kind text not null default 'spend' check (kind in ('grant','spend','refund','admin')),
  ref_type text,
  ref_id text,
  note text default '',
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- gift_rarities: hierarquia de raridade (configurável pelo backend).
-- ---------------------------------------------------------------------------
create table if not exists public.gift_rarities (
  id text primary key,
  name text not null,
  emoji text default '',
  "order" int not null default 0,
  color text default '#FFFFFF',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- gift_categories: categorias do catálogo (40+ seed; mais via painel).
-- ---------------------------------------------------------------------------
create table if not exists public.gift_categories (
  id text primary key,
  name text not null,
  emoji text default '',
  "order" int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- gift_effects: presets de animação reutilizáveis (evitam duplicar arquivos).
-- Cada presente referencia um preset de animação (animation_key) + params.
-- ---------------------------------------------------------------------------
create table if not exists public.gift_effects (
  id text primary key,
  name text not null,
  kind text not null default 'preset' check (kind in ('preset','custom')),
  params jsonb not null default '{}',
  tier int not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- gift_events: eventos/edições que agrupam presentes (datas comemorativas etc).
-- ---------------------------------------------------------------------------
create table if not exists public.gift_events (
  id text primary key,
  name text not null,
  description text default '',
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- gifts: o catálogo em si. Escalável por linhas (não por arquivos/APK).
-- ---------------------------------------------------------------------------
create table if not exists public.gifts (
  id text primary key,
  name text not null,
  category_id text not null,
  rarity_id text not null,
  credits bigint not null default 0 check (credits >= 0),
  icon text not null default '🎁',
  glyph text default '',
  animation_key text default 'sparkle',
  effects jsonb not null default '{}',
  description text default '',
  status text not null default 'active' check (status in ('active','inactive')),
  sort_order int not null default 0,
  is_featured boolean not null default false,
  is_exclusive boolean not null default false,
  is_temporary boolean not null default false,
  is_event_gift boolean not null default false,
  is_limited boolean not null default false,
  is_tradable boolean not null default true,
  regions text[] not null default '{}',
  event_id text references public.gift_events(id) on delete set null,
  featured_start timestamptz,
  featured_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint gifts_category_fk foreign key (category_id) references public.gift_categories(id),
  constraint gifts_rarity_fk foreign key (rarity_id) references public.gift_rarities(id)
);

-- ---------------------------------------------------------------------------
-- gift_event_items: N:N presentes <-> eventos (um presente pode estar em vários).
-- ---------------------------------------------------------------------------
create table if not exists public.gift_event_items (
  gift_id text not null references public.gifts(id) on delete cascade,
  event_id text not null references public.gift_events(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (gift_id, event_id)
);

-- ---------------------------------------------------------------------------
-- gift_favorites: favoritos do usuário.
-- ---------------------------------------------------------------------------
create table if not exists public.gift_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  gift_id text not null references public.gifts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, gift_id)
);

-- ---------------------------------------------------------------------------
-- gift_inventory: presentes possuídos/colecionáveis (ex.: exclusivos limitados).
-- ---------------------------------------------------------------------------
create table if not exists public.gift_inventory (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  gift_id text not null references public.gifts(id) on delete cascade,
  quantity int not null default 0,
  source text default '',
  acquired_at timestamptz not null default now(),
  unique (user_id, gift_id)
);

-- ---------------------------------------------------------------------------
-- gift_transactions: histórico financeiro autoritativo de envio de presentes.
-- (A tabela `live_gifts` já registra o presente recebido na live; esta guarda
--  o registro financeiro completo com saldo e custo.)
-- ---------------------------------------------------------------------------
create table if not exists public.gift_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid references auth.users(id) on delete set null,
  live_id uuid references public.lives(id) on delete set null,
  gift_id text not null references public.gifts(id),
  gift_name text not null,
  amount int not null default 1 check (amount > 0),
  credits_per_unit bigint not null default 0,
  credits_total bigint not null default 0,
  balance_after bigint not null default 0,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- gift_usage_stats: agregados para "populares / tendências / recomendados".
-- Incrementados pelo backend (service role) em cada envio.
-- ---------------------------------------------------------------------------
create table if not exists public.gift_usage_stats (
  gift_id text primary key references public.gifts(id) on delete cascade,
  sent_count bigint not null default 0,
  received_count bigint not null default 0,
  last_sent_at timestamptz,
  last_received_at timestamptz,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Indexes (performance para catálogo 50k+/100k+ e paginação)
-- ---------------------------------------------------------------------------
create index if not exists gifts_category_idx on public.gifts (category_id, sort_order, id);
create index if not exists gifts_rarity_idx on public.gifts (rarity_id, sort_order, id);
create index if not exists gifts_status_idx on public.gifts (status, sort_order, id);
create index if not exists gifts_featured_idx on public.gifts (is_featured) where is_featured and status = 'active';
create index if not exists gifts_exclusive_idx on public.gifts (is_exclusive) where is_exclusive and status = 'active';
create index if not exists gifts_event_idx on public.gifts (event_id);
create index if not exists gifts_region_idx on public.gifts using gin (regions);
create index if not exists gifts_name_idx on public.gifts using gin (to_tsvector('portuguese', name));
create index if not exists credit_tx_user_idx on public.credit_transactions (user_id, created_at desc);
create index if not exists gift_tx_user_idx on public.gift_transactions (user_id, created_at desc);
create index if not exists gift_tx_receiver_idx on public.gift_transactions (receiver_id, created_at desc);
create index if not exists gift_tx_live_idx on public.gift_transactions (live_id);
create index if not exists gift_tx_gift_idx on public.gift_transactions (gift_id);
create index if not exists fav_user_idx on public.gift_favorites (user_id);
create index if not exists inv_user_idx on public.gift_inventory (user_id);
create index if not exists events_times_idx on public.gift_events (active, starts_at, ends_at);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.user_wallets enable row level security;
alter table public.credit_transactions enable row level security;
alter table public.gift_rarities enable row level security;
alter table public.gift_categories enable row level security;
alter table public.gift_effects enable row level security;
alter table public.gift_events enable row level security;
alter table public.gifts enable row level security;
alter table public.gift_event_items enable row level security;
alter table public.gift_favorites enable row level security;
alter table public.gift_inventory enable row level security;
alter table public.gift_transactions enable row level security;
alter table public.gift_usage_stats enable row level security;

-- Catálogo (rarities/categories/effects/events/gifts) é de leitura pública.
-- Escrita é exclusiva do service role (painel administrativo), que ignora RLS.
drop policy if exists "gift_rarities_select" on public.gift_rarities;
create policy "gift_rarities_select" on public.gift_rarities for select using (true);
drop policy if exists "gift_categories_select" on public.gift_categories;
create policy "gift_categories_select" on public.gift_categories for select using (true);
drop policy if exists "gift_effects_select" on public.gift_effects;
create policy "gift_effects_select" on public.gift_effects for select using (true);
drop policy if exists "gift_events_select" on public.gift_events;
create policy "gift_events_select" on public.gift_events for select using (true);
drop policy if exists "gifts_select" on public.gifts;
create policy "gifts_select" on public.gifts for select using (true);
drop policy if exists "gift_event_items_select" on public.gift_event_items;
create policy "gift_event_items_select" on public.gift_event_items for select using (true);
drop policy if exists "gift_usage_stats_select" on public.gift_usage_stats;
create policy "gift_usage_stats_select" on public.gift_usage_stats for select using (true);

-- Favoritos: dono gerencia os próprios.
drop policy if exists "gift_favorites_select" on public.gift_favorites;
drop policy if exists "gift_favorites_insert" on public.gift_favorites;
drop policy if exists "gift_favorites_delete" on public.gift_favorites;
create policy "gift_favorites_select" on public.gift_favorites for select using (user_id = auth.uid());
create policy "gift_favorites_insert" on public.gift_favorites for insert with check (user_id = auth.uid());
create policy "gift_favorites_delete" on public.gift_favorites for delete using (user_id = auth.uid());

-- Inventário: dono lê o próprio.
drop policy if exists "gift_inventory_select" on public.gift_inventory;
create policy "gift_inventory_select" on public.gift_inventory for select using (user_id = auth.uid());

-- Histórico: dono lê o próprio; quem recebeu lê o que recebeu.
drop policy if exists "gift_transactions_select_own" on public.gift_transactions;
create policy "gift_transactions_select_own" on public.gift_transactions
  for select using (user_id = auth.uid() or receiver_id = auth.uid());

-- Wallet: dono lê o próprio saldo. Ninguém escreve via RLS (só service role).
drop policy if exists "user_wallets_select" on public.user_wallets;
create policy "user_wallets_select" on public.user_wallets for select using (user_id = auth.uid());

-- Livro-caixa: dono lê o próprio histórico de créditos.
drop policy if exists "credit_transactions_select" on public.credit_transactions;
create policy "credit_transactions_select" on public.credit_transactions
  for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Função: grant de créditos iniciais na criação do usuário (via trigger).
-- O valor é um bônus de boas-vindas configurável; só o backend escreve saldo.
-- ---------------------------------------------------------------------------
create or replace function public.grant_initial_credits()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.user_wallets (user_id, credits) values (new.id, 100)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists grant_initial_credits_trigger on auth.users;
create trigger grant_initial_credits_trigger
  after insert on auth.users
  for each row execute function public.grant_initial_credits();

-- Garante wallet para usuários já existentes que não a tenham.
insert into public.user_wallets (user_id, credits)
select u.id, 100 from auth.users u
left join public.user_wallets w on w.user_id = u.id
where w.user_id is null
on conflict (user_id) do nothing;

-- ---------------------------------------------------------------------------
-- Seeds: raridades (hierarquia própria KLAY K)
-- ---------------------------------------------------------------------------
insert into public.gift_rarities (id, name, emoji, "order", color) values
  ('comum',    'Comum',              '⚪', 1,  '#B0BEC5'),
  ('incomum',  'Incomum',            '🟢', 2,  '#66BB6A'),
  ('especial', 'Especial',           '💜', 3,  '#AB47BC'),
  ('raro',     'Raro',               '🔵', 4,  '#42A5F5'),
  ('epico',    'Épico',              '💎', 5,  '#7E57C2'),
  ('mitico',   'Mítico',             '🔥', 6,  '#FF7043'),
  ('lendario', 'Lendário',           '👑', 7,  '#FFB300'),
  ('exclusivo','Exclusivo KLAY K',   '🌟', 8,  '#29B6F6'),
  ('ultra',    'A.R.H TECH Ultra',   '👑', 9,  '#D4AF37')
on conflict (id) do update set name = excluded.name, emoji = excluded.emoji, "order" = excluded."order", color = excluded.color;

-- ---------------------------------------------------------------------------
-- Seeds: categorias (40)
-- ---------------------------------------------------------------------------
insert into public.gift_categories (id, name, emoji, "order") values
  ('comuns',       'Comuns',              '🎁', 1),
  ('especiais',    'Especiais',           '💜', 2),
  ('raros',        'Raros',               '⭐', 3),
  ('epicos',       'Épicos',              '💎', 4),
  ('lendarios',    'Lendários',           '👑', 5),
  ('temporarios',  'Temporários / Eventos','🔥', 6),
  ('datas',        'Datas comemorativas', '🎉', 7),
  ('games',        'Games',               '🎮', 8),
  ('romanticos',   'Românticos',          '❤️', 9),
  ('divertidos',   'Divertidos',          '😂', 10),
  ('exclusivos',   'Exclusivos KLAY K',   '🌟', 11),
  ('tecnologia',   'Tecnologia',          '💡', 12),
  ('planetas',     'Planetas / Universo', '🌍', 13),
  ('ceo',          'CEO A.R.H TECH',      '👑', 14),
  ('dragoes',      'Dragões',             '🐉', 15),
  ('fogo',         'Fogo e Energia',      '🔥', 16),
  ('joias',        'Diamantes e Joias',   '💎', 17),
  ('realeza',      'Realeza',             '👑', 18),
  ('magicas',      'Criaturas Mágicas',   '🪽', 19),
  ('carros',       'Carros e Velocidade', '🚗', 20),
  ('aviacao',      'Aviação',             '✈️', 21),
  ('maritimos',    'Marítimos',           '🚢', 22),
  ('cidades',      'Cidades e Arquitetura','🏙️', 23),
  ('tesouros',     'Tesouros',            '💰', 24),
  ('esportes',     'Esportes',            '⚽', 25),
  ('musica',       'Música',              '🎵', 26),
  ('cinema',       'Cinema',              '🎬', 27),
  ('comidas',      'Comidas',             '🍔', 28),
  ('cafedoces',    'Café e Doces',        '☕', 29),
  ('oceano',       'Oceano',              '🌊', 30),
  ('natureza',     'Natureza e Clima',    '🌈', 31),
  ('eventos',      'Eventos e Datas',     '🎄', 32),
  ('magia',        'Magia e Fantasia',    '🔮', 33),
  ('extraterrestre','Extraterrestres',    '👽', 34),
  ('flores',       'Flores e Vida',       '🦋', 35),
  ('dimensoes',    'Dimensões e Tempo',   '🌀', 36),
  ('reinoceu',     'Reino dos Céus',      '✝️', 37),
  ('anjos',        'Anjos',               '👼', 38),
  ('fe',           'Fé e Esperança',      '🙏', 39),
  ('luzcelestial', 'Luz Celestial',       '🌟', 40)
on conflict (id) do update set name = excluded.name, emoji = excluded.emoji, "order" = excluded."order";

-- ---------------------------------------------------------------------------
-- Seeds: presets de efeito/animação reutilizáveis
-- ---------------------------------------------------------------------------
insert into public.gift_effects (id, name, kind, params, tier) values
  ('sparkle',       'Brilho',             'preset', '{"enter":"fade","main":"sparkle"}'::jsonb, 1),
  ('heartburst',    'Corações',           'preset', '{"enter":"pop","main":"hearts"}'::jsonb, 1),
  ('starfall',      'Chuva de Estrelas',  'preset', '{"enter":"fall","main":"stars"}'::jsonb, 2),
  ('diamondrain',   'Chuva de Diamantes', 'preset', '{"enter":"fall","main":"diamonds"}'::jsonb, 3),
  ('fireflight',    'Voo de Fogo',        'preset', '{"enter":"flame","main":"fire"}'::jsonb, 4),
  ('cosmicgate',    'Portal Cósmico',     'preset', '{"enter":"portal","main":"cosmic"}'::jsonb, 7),
  ('dragoncelestial','Dragão Celestial',  'custom', '{"enter":"portal","main":"dragon","trail":"golden"}'::jsonb, 9),
  ('royalthrone',   'Trono Imperial',     'custom', '{"enter":"rise","main":"royal"}'::jsonb, 9),
  ('supernova',     'Supernova',          'preset', '{"enter":"explode","main":"nova"}'::jsonb, 8)
on conflict (id) do update set name = excluded.name, params = excluded.params, tier = excluded.tier;

-- ---------------------------------------------------------------------------
-- Seeds: eventos de exemplo
-- ---------------------------------------------------------------------------
insert into public.gift_events (id, name, description, active) values
  ('lancamento', 'Lançamento KLAY K', 'Evento de lançamento com presentes exclusivos.', true),
  ('diamantes',  'Festival de Diamantes', 'Presentes de joias em destaque.', true)
on conflict (id) do update set name = excluded.name;

-- ---------------------------------------------------------------------------
-- Seeds: presentes iniciais do catálogo (amostra real, criados no banco).
-- A arquitetura suporta 50k+ simplesmente inserindo mais linhas via painel.
-- ---------------------------------------------------------------------------
-- dragão lendário celestial
insert into public.gifts (id, name, category_id, rarity_id, credits, icon, glyph, animation_key, effects, description, sort_order, is_featured, is_exclusive, is_limited, is_tradable) values
  ('dragao-lendario-celestial', 'Dragão Lendário Celestial', 'dragoes', 'ultra', 50000, '🐉', 'DLC', 'dragoncelestial', '{"color":"#FFD700","trail":"#FFE082"}'::jsonb,
   'Um dragão celestial amarelo/dourado de aparência majestosa. Ele atravessa o portal dourado, circunda a transmissão deixando um rastro de partículas douradas e revela o seu nome e o do remetente em uma entrada cinematográfica. Exclusivo da coleção A.R.H TECH.', 1, true, true, true, false),
  ('coroa-suprema-arh', 'Coroa Suprema A.R.H', 'ceo', 'ultra', 88888, '👑', 'CSA', 'royalthrone', '{"color":"#D4AF37"}'::jsonb, 'A coroa definitiva do CEO A.R.H TECH. Ultrafrara, exclusiva e limitada.', 2, true, true, true, false),
  ('galaxia-arh', 'Galáxia A.R.H', 'ceo', 'ultra', 99999, '🌌', 'GAR', 'supernova', '{"color":"#7C4DFF"}'::jsonb, 'Uma galáxia inteira dentro do seu universo. Exclusivo A.R.H TECH.', 3, true, true, true, false),
  ('universo-arh', 'Universo A.R.H', 'ceo', 'ultra', 120000, '🌠', 'UAR', 'cosmicgate', '{"color":"#448AFF"}'::jsonb, 'O universo em toda a sua glória. Presente máximo A.R.H TECH.', 4, true, true, true, false),
  ('klayk-galaxy', 'KLAY K Galaxy', 'exclusivos', 'exclusivo', 25000, '🌌', 'KGA', 'cosmicgate', '{"color":"#29B6F6"}'::jsonb, 'A galáxia KLAY K, exclusiva da marca.', 5, true, true, false, true),
  ('klayk-crown', 'KLAY K Crown', 'exclusivos', 'exclusivo', 30000, '👑', 'KCR', 'royalthrone', '{"color":"#FFD700"}'::jsonb, 'A coroa oficial do KLAY K.', 6, true, true, false, true),
  ('klayk-supernova', 'KLAY K Supernova', 'exclusivos', 'exclusivo', 40000, '💥', 'KSU', 'supernova', '{"color":"#FFC107"}'::jsonb, 'A supernova exclusiva do KLAY K.', 7, true, true, false, true),
  ('dragao-celestial', 'Dragão Celestial', 'dragoes', 'lendario', 15000, '🐉', 'DCE', 'dragoncelestial', '{"color":"#FDD835"}'::jsonb, 'O dragão celestial guardião dos céus.', 8, true, false, false, true),
  ('dragao-cosmico', 'Dragão Cósmico', 'dragoes', 'lendario', 18000, '🐲', 'DCO', 'cosmicgate', '{"color":"#7C4DFF"}'::jsonb, 'Dragão que navega entre as galáxias.', 9, false, false, false, true),
  ('fenix-dourada', 'Fênix Dourada', 'magicas', 'lendario', 20000, '🦅', 'FDO', 'fireflight', '{"color":"#FFB300"}'::jsonb, 'A fênix renascida nas chamas douradas.', 10, false, false, false, true),
  ('diamante-roxo', 'Diamante Roxo', 'joias', 'epico', 8000, '💎', 'DRX', 'diamondrain', '{"color":"#AB47BC"}'::jsonb, 'Um diamante de raro brilho violeta.', 11, false, false, false, true),
  ('diamante-celestial', 'Diamante Celestial', 'joias', 'lendario', 16000, '🔷', 'DCE2', 'diamondrain', '{"color":"#42A5F5"}'::jsonb, 'Diamante que reflete a luz dos céus.', 12, false, false, false, true),
  ('robô-klayk', 'Robô KLAY K', 'tecnologia', 'raro', 5000, '🤖', 'RBO', 'sparkle', '{"color":"#00BCD4"}'::jsonb, 'O robô oficial do KLAY K.', 13, false, false, false, true),
  ('foguete-klayk', 'Foguete KLAY K', 'exclusivos', 'epico', 9000, '🚀', 'FOG', 'starfall', '{"color":"#FF5722"}'::jsonb, 'Foguete KLAY K rumo às estrelas.', 14, false, true, false, true),
  ('coracao-dourado', 'Coração Dourado', 'romanticos', 'especial', 2000, '💛', 'CDO', 'heartburst', '{"color":"#FFD700"}'::jsonb, 'Um coração de ouro puro para quem você ama.', 15, false, false, false, true),
  ('coracao-cosmico', 'Coração Cósmico', 'romanticos', 'epico', 10000, '💜', 'CCO', 'heartburst', '{"color":"#7C4DFF"}'::jsonb, 'Um coração que abraça o cosmos.', 16, false, true, false, true),
  ('trofeu-klayk', 'Troféu KLAY K', 'esportes', 'raro', 6000, '🏆', 'TRO', 'royalthrone', '{"color":"#FFD700"}'::jsonb, 'Troféu oficial de campeonatos KLAY K.', 17, false, false, false, true),
  ('perola-cosmica', 'Pérola Cósmica', 'oceano', 'epico', 7000, '🦪', 'PCO', 'sparkle', '{"color":"#B2EBF2"}'::jsonb, 'Uma pérola formada no oceano das estrelas.', 18, false, false, false, true),
  ('fenix-imperial-arh', 'Fênix Imperial A.R.H', 'ceo', 'ultra', 75000, '🦅', 'FIA', 'fireflight', '{"color":"#FF7043"}'::jsonb, 'A fênix imperial da coroa A.R.H.', 19, false, true, true, false),
  ('dragao-solar-arh', 'Dragão Solar A.R.H', 'ceo', 'ultra', 65000, '🐉', 'DSA', 'dragoncelestial', '{"color":"#FFAB00"}'::jsonb, 'Dragão forjado no núcleo solar. Exclusivo A.R.H.', 20, false, true, true, false),
  ('rosa-dourada', 'Rosa Dourada', 'romanticos', 'especial', 2500, '🌹', 'RDO', 'sparkle', '{"color":"#FFD700"}'::jsonb, 'Rosa eterna de pétalas douradas.', 21, false, false, false, true),
  ('galaxia-roxa', 'Galáxia Roxa', 'planetas', 'epico', 12000, '🌌', 'GRA', 'cosmicgate', '{"color":"#9C27B0"}'::jsonb, 'Uma galáxia de tom violeta profundo.', 22, false, false, false, true),
  ('sol-imperial', 'Sol Imperial', 'planetas', 'lendario', 14000, '☀️', 'SIP', 'supernova', '{"color":"#FFB300"}'::jsonb, 'O sol em toda a sua majestade imperial.', 23, false, false, false, true),
  ('lua-roxo', 'Lua Roxa', 'planetas', 'especial', 3000, '🌙', 'LRX', 'starfall', '{"color":"#AB47BC"}'::jsonb, 'A lua banhada em luz violeta.', 24, false, false, false, true)
on conflict (id) do update set
  name = excluded.name, category_id = excluded.category_id, rarity_id = excluded.rarity_id,
  credits = excluded.credits, icon = excluded.icon, animation_key = excluded.animation_key,
  description = excluded.description, is_featured = excluded.is_featured,
  is_exclusive = excluded.is_exclusive, is_limited = excluded.is_limited, is_tradable = excluded.is_tradable,
  updated_at = now();

-- Seed de uso popular inicial (vem do backend real após movimentações; aqui
-- apenas um mínimo para ordenar a página de "populares" nos primeiros momentos).
insert into public.gift_usage_stats (gift_id, sent_count) values
  ('dragao-lendario-celestial', 0),
  ('coracao-dourado', 0),
  ('trofeu-klayk', 0),
  ('klayk-galaxy', 0)
on conflict (gift_id) do nothing;
