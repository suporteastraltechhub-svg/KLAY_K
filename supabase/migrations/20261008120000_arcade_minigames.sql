-- KLAY K · minijogos arcade recreativos
--
-- 8 novos jogos na tela "Jogos". Todos são EXCLUSIVAMENTE recreativos:
-- a pontuação é virtual e o XP é o mesmo sistema de níveis já usado pelo app
-- (creditado pela RPC `game_submit_score`). NÃO existe aposta, depósito, saque,
-- prêmio financeiro, conversão de créditos para dinheiro, compra de jogadas,
-- PIX nem qualquer integração de BET/cassino.
--
-- Cada linha registra `engine` (a tela que abre em game_router.dart) e
-- `max_score` (teto da pontuação). O botão JOGAR sempre abre uma mecânica
-- funcional — nenhum placeholder.

insert into public.games
  (id, name, description, emoji, category, status, engine, rules, max_score, sort_order)
values
  ('klayk_slot', 'Slot KLAY K',
   'Três roles com símbolos do KLAY K. Combinações de 3 a 6 símbolos iguais rendem pontos virtuais. Sem aposta: você só toca em GIRAR.',
   '🎰', 'arcade', 'active', 'slot',
   '{"difficulty": 1, "duration_seconds": 120, "engine_config": {"reels": 3}}'::jsonb,
   1000, 20),

  ('klayk_roda', 'Roda KLAY K',
   'Roda de oito segmentos com recompensa virtual: XP, créditos internos, bônus e multiplicadores. Sem compra de giros e sem valor financeiro.',
   '🎡', 'sorte', 'active', 'roda',
   '{"difficulty": 1, "duration_seconds": 120, "engine_config": {"segments": 8}}'::jsonb,
   1000, 21),

  ('klayk_dados', 'Dados KLAY K',
   'Escolha ímpar ou par e role os dois dados. A pontuação virtual depende do acerto e da soma. Nada é descontado.',
   '🎲', 'sorte', 'active', 'dados',
   '{"difficulty": 2, "duration_seconds": 120, "engine_config": {"picks": ["impar", "par"]}}'::jsonb,
   1000, 22),

  ('klayk_cartas', 'Cartas KLAY K',
   'Memória com cartas próprias do KLAY K. Acertos seguidos formam combo e multiplicam os pontos virtuais.',
   '🃏', 'quebra-cabeca', 'active', 'cartas_arcade',
   '{"difficulty": 2, "duration_seconds": 180, "engine_config": {"pairs": 8}}'::jsonb,
   1000, 23),

  ('klayk_mines', 'Mines KLAY K',
   'Grade com bombas virtuais. Abra casas seguras para acumular pontos e use GUARDAR PONTOS para encerrar a rodada. A pontuação começa em zero: não há aposta nem perda de dinheiro.',
   '💣', 'habilidade', 'active', 'mines',
   '{"difficulty": 3, "duration_seconds": 180, "engine_config": {"grid": 5, "mines": 4}}'::jsonb,
   1000, 24),

  ('klayk_crash', 'Crash KLAY K',
   'O multiplicador começa em 1x e sobe. Toque em COLETAR antes do fim para registrar a pontuação virtual da rodada. Sem aposta e sem dinheiro.',
   '🚀', 'arcade', 'active', 'crash',
   '{"difficulty": 3, "duration_seconds": 180, "engine_config": {"min": 1.6, "max": 6.0}}'::jsonb,
   1000, 25),

  ('klayk_bau', 'Baú Surpresa',
   'Abra o baú e ganhe uma recompensa virtual aleatória: XP, créditos internos ou item cosmético. Não existe compra de baú.',
   '🎁', 'sorte', 'active', 'bau',
   '{"difficulty": 1, "duration_seconds": 120, "engine_config": {"prizes": 6}}'::jsonb,
   1000, 26),

  ('klayk_moeda', 'Cara ou Coroa',
   'Escolha um lado, gire a moeda e ganhe pontos virtuais se acertar. Partida de poucos segundos.',
   '🪙', 'sorte', 'active', 'moeda',
   '{"difficulty": 1, "duration_seconds": 90, "engine_config": {"sides": 2}}'::jsonb,
   1000, 27)
on conflict (id) do update set
  name = excluded.name,
  description = excluded.description,
  emoji = excluded.emoji,
  category = excluded.category,
  status = excluded.status,
  engine = excluded.engine,
  rules = excluded.rules,
  max_score = excluded.max_score,
  sort_order = excluded.sort_order;

-- Categorias novas usadas acima. Se a tabela de categorias não existir no
-- schema, o bloco é inerte e a tela cai no filtro por `games.category`.
do $$
begin
  if to_regclass('public.game_categories') is not null then
    insert into public.game_categories (id, label, emoji, sort_order)
    values
      ('arcade', '🎰 Arcade', '🎰', 1),
      ('habilidade', '🎯 Habilidade', '🎯', 2),
      ('sorte', '🎲 Sorte', '🎲', 3),
      ('quebra-cabeca', '🧩 Quebra-cabeças', '🧩', 4),
      ('em-alta', '🔥 Em alta', '🔥', 0),
      ('novos', '🆕 Novos', '🆕', 1)
    on conflict (id) do update set
      label = excluded.label,
      emoji = excluded.emoji,
      sort_order = excluded.sort_order;
  end if;
end
$$;