-- ============================================================================
-- KLAY K — CATÁLOGO DE JOGOS POR ENGINE REUTILIZÁVEL
--  * Adiciona games.engine (define QUAL engine executa o jogo no app).
--  * Reutiliza TODO o backend existente (games, game_sessions, game_scores,
--    game_start_session, game_submit_score) — sem novos saldos nem RPC de
--    escrita. Cada jogo é apenas CONFIGURAÇÃO (rules.engine_config) sobre uma
--    das 7 engines (trivia/reflexo/memoria/matematica/palavras/arcade/
--    estrategia). Adicionar o 701º jogo = 1 insert, não uma nova tela.
--  * game_popularity: contagem REAL de partidas (seção "Em alta") — leitura.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Engine por jogo
-- ---------------------------------------------------------------------------
alter table public.games
  add column if not exists engine text not null default 'trivia';

create index if not exists games_engine_idx on public.games (engine);
create index if not exists games_category_idx on public.games (category);

-- ---------------------------------------------------------------------------
-- 2) População real ("Em alta"): nº de partidas por jogo.
--    Somente leitura agregada — não expõe saldos nem dados pessoais.
-- ---------------------------------------------------------------------------
create or replace function public.game_popularity()
returns table (game_id text, plays bigint)
language sql
security definer
set search_path = public
as $$
  select gs.game_id, count(*)::bigint as plays
    from public.game_sessions gs
   group by gs.game_id
   order by plays desc;
$$;

revoke all on function public.game_popularity() from public;
grant execute on function public.game_popularity() to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Catálogo: padroniza categorias e integra os jogos às engines.
--    Reutiliza os jogos existentes (prioridade) e adiciona novos como dados.
-- ---------------------------------------------------------------------------
insert into public.games
  (id, name, description, emoji, category, status, engine, rules, max_score, sort_order)
values
  -- Trivia (engine trivia) — Quiz existente + novos quizzes reais
  ('quiz', 'Quiz KLAY K', 'Teste seus conhecimentos em 6 perguntas rápidas.', '🧠', 'trivia', 'active', 'trivia',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 6, 'crystals', 3), jsonb_build_object('min_score', 4, 'crystals', 2)),
      'difficulty', 1, 'duration_seconds', 90,
      'engine_config', jsonb_build_object('questions', jsonb_build_array(
        jsonb_build_array('Qual é a capital do Brasil?', 'Rio de Janeiro', 'Brasília', 'São Paulo', 'Salvador', 1),
        jsonb_build_array('Quantos estados tem o Brasil?', '25', '26', '27', '32', 2),
        jsonb_build_array('Quem pintou a "Monalisa"?', 'Van Gogh', 'Picasso', 'Da Vinci', 'Michelangelo', 2),
        jsonb_build_array('Qual é o maior planeta do Sistema Solar?', 'Terra', 'Júpiter', 'Saturno', 'Netuno', 1),
        jsonb_build_array('Quantos minutos tem 1h30?', '60', '80', '90', '120', 2),
        jsonb_build_array('Qual animal é o símbolo da sabedoria?', 'Leão', 'Gato', 'Coruja', 'Tigre', 2)
      ))
    ), 6, 1),

  ('ciencias', 'Quiz de Ciências', 'Perguntas reais de ciências para testar o que você sabe.', '🔬', 'trivia', 'active', 'trivia',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 6, 'crystals', 3), jsonb_build_object('min_score', 4, 'crystals', 2)),
      'difficulty', 1, 'duration_seconds', 120,
      'engine_config', jsonb_build_object('questions', jsonb_build_array(
        jsonb_build_array('Qual é o símbolo químico do ouro?', 'Au', 'Ag', 'Fe', 'Cu', 0),
        jsonb_build_array('Qual gás os seres humanos inalam para respirar?', 'Gás carbônico', 'Nitrogênio', 'Oxigênio', 'Hidrogênio', 2),
        jsonb_build_array('Qual é o planeta conhecido como "Planeta Vermelho"?', 'Vênus', 'Marte', 'Júpiter', 'Mercúrio', 1),
        jsonb_build_array('Quantos ossos tem o corpo humano adulto?', '106', '206', '256', '306', 1),
        jsonb_build_array('Qual é a fonte natural de energia da Terra?', 'Lua', 'Sol', 'Terra', 'Estrelas', 1),
        jsonb_build_array('Qual é a velocidade aproximada da luz?', '300.000 km/s', '150.000 km/s', '30.000 km/s', '3.000 km/s', 0)
      ))
    ), 6, 10),

  ('filmes', 'Quiz de Filmes', 'Perguntas reais sobre filmes que todo mundo ama.', '🎬', 'trivia', 'active', 'trivia',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 6, 'crystals', 3), jsonb_build_object('min_score', 4, 'crystals', 2)),
      'difficulty', 2, 'duration_seconds', 120,
      'engine_config', jsonb_build_object('questions', jsonb_build_array(
        jsonb_build_array('Qual filme tem a frase "Que a força esteja com você"?', 'Vingadores', 'Star Wars', 'Matrix', 'Senhor dos Anéis', 1),
        jsonb_build_array('Quem interpreta o Homem de Ferro?', 'Chris Evans', 'Chris Hemsworth', 'Robert Downey Jr.', 'Mark Ruffalo', 2),
        jsonb_build_array('Em "O Rei Leão", qual é o nome do pai de Simba?', 'Scar', 'Mufasa', 'Timão', 'Zazu', 1),
        jsonb_build_array('Qual rapper estrelou "8 Mile"?', 'Jay-Z', '50 Cent', 'Eminem', 'Snoop Dogg', 2),
        jsonb_build_array('Qual é o nome do feiticeiro de Harry Potter?', 'Dumbledore', 'Voldemort', 'Snape', 'Hagrid', 0),
        jsonb_build_array('Qual animação é ambientada no fundo do oceano?', 'Frozen', 'Moana', 'Procurando Nemo', 'Toy Story', 2)
      ))
    ), 6, 11),

  ('historia', 'Quiz de História', 'Fatos históricos reais do Brasil e do mundo.', '🏛️', 'trivia', 'active', 'trivia',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 6, 'crystals', 3), jsonb_build_object('min_score', 4, 'crystals', 2)),
      'difficulty', 2, 'duration_seconds', 120,
      'engine_config', jsonb_build_object('questions', jsonb_build_array(
        jsonb_build_array('Em que ano o Brasil foi descoberto?', '1500', '1492', '1530', '1550', 0),
        jsonb_build_array('Quem proclamou a Independência do Brasil?', 'Dom Pedro I', 'Dom Pedro II', 'Getúlio Vargas', 'Tiradentes', 0),
        jsonb_build_array('Qual civilização construiu as pirâmides?' , 'Maia', 'Egípcia', 'Inca', 'Romana', 1),
        jsonb_build_array('Quantos anos durou a Segunda Guerra Mundial?', '4', '5', '6', '7', 2),
        jsonb_build_array('Qual é o maior império da história?', 'Romano', 'Mongol', 'Britânico', 'Espartano', 2),
        jsonb_build_array('Quem foi o primeiro homem a pisar na Lua?', 'Buzz Aldrin', 'Yuri Gagarin', 'Neil Armstrong', 'Michael Collins', 2)
      ))
    ), 6, 12),

  ('futebol', 'Quiz de Futebol', 'Perguntas reais para os apaixonados por futebol.', '⚽', 'esportes', 'active', 'trivia',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 6, 'crystals', 3), jsonb_build_object('min_score', 4, 'crystals', 2)),
      'difficulty', 2, 'duration_seconds', 120,
      'engine_config', jsonb_build_object('questions', jsonb_build_array(
        jsonb_build_array('Qual país ganhou a Copa do Mundo de 2002?', 'Brasil', 'Alemanha', 'França', 'Argentina', 0),
        jsonb_build_array('Quantos jogadores tem um time de futebol?', '9', '10', '11', '12', 2),
        jsonb_build_array('Qual jogador é conhecido como "Rei do Futebol"?', 'Pelé', 'Maradona', 'Messi', 'CR7', 0),
        jsonb_build_array('Qual é a duração de uma partida oficial (sem tempo extra)?', '60 min', '80 min', '90 min', '120 min', 2),
        jsonb_build_array('Qual clube brasileiro é chamado de "Timão"?', 'Palmeiras', 'Flamengo', 'Corinthians', 'São Paulo', 2),
        jsonb_build_array('Em que país foi a Copa de 2014?', 'Alemanha', 'Brasil', 'Rússia', 'Catar', 1)
      ))
    ), 6, 13),

  ('hits', 'Quiz Musical', 'Teste seu conhecimento de música e artistas.', '🎵', 'musica', 'active', 'trivia',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 6, 'crystals', 3), jsonb_build_object('min_score', 4, 'crystals', 2)),
      'difficulty', 2, 'duration_seconds', 120,
      'engine_config', jsonb_build_object('questions', jsonb_build_array(
        jsonb_build_array('Qual artista é conhecido como "Rainha do Pop"?', 'Beyoncé', 'Madonna', 'Rihanna', 'Lady Gaga', 1),
        jsonb_build_array('Qual dupla canta "Evidências"?', 'Zeze Di Camargo & Luciano', 'Chitãozinho & Xororó', 'Bruno & Marrone', 'Jorge & Mateus', 1),
        jsonb_build_array('Qual banda canta "Bohemian Rhapsody"?', 'The Beatles', 'Queen', 'Rolling Stones', 'AC/DC', 1),
        jsonb_build_array('Quantas cordas tem um violão clássico?', '4', '5', '6', '7', 2),
        jsonb_build_array('Qual é o nome do álbum de estreia de Taylor Swift?', 'Fearless', 'Taylor Swift', 'Red', '1989', 1),
        jsonb_build_array('Qual cantor é apelidado de "Trap do Funk"?', 'MC Kevinho', 'Matuê', 'Anitta', 'Ludmilla', 1)
      ))
    ), 6, 14),

  -- Reflexo (engine reflexo) — Toque rápido existente + novos
  ('toque', 'Toque Rápido', 'Toque o alvo o máximo de vezes em 15 segundos.', '⚡', 'reflexo', 'active', 'reflexo',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 10, 'crystals', 2), jsonb_build_object('min_score', 15, 'crystals', 4)),
      'difficulty', 1, 'duration_seconds', 15, 'max_visible', 40, 'shrink', true,
      'engine_config', jsonb_build_object('duration_seconds', 15, 'shrink_every', 5, 'tint', '#E4183C')
    ), 40, 2),

  ('reagir', 'Reação', 'Toque o alvo o mais rápido possível em 10 segundos.', '🎯', 'reflexo', 'active', 'reflexo',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 8, 'crystals', 2), jsonb_build_object('min_score', 14, 'crystals', 3)),
      'difficulty', 1, 'duration_seconds', 10, 'max_visible', 30, 'shrink', true,
      'engine_config', jsonb_build_object('duration_seconds', 10, 'shrink_every', 4, 'tint', '#38BDF8')
    ), 30, 21),

  ('turbo', 'Turbo Reativo', 'Acelere tocando o combustível — reflexos de piloto.', '🏎️', 'corrida', 'active', 'reflexo',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 20, 'crystals', 2), jsonb_build_object('min_score', 35, 'crystals', 4)),
      'difficulty', 2, 'duration_seconds', 20, 'max_visible', 60, 'shrink', false,
      'engine_config', jsonb_build_object('duration_seconds', 20, 'shrink_every', 0, 'tint', '#F59E0B')
    ), 60, 32),

  -- Memória (engine memoria) — Memória existente + novos
  ('memoria', 'Memória', 'Combine os pares de cartas no menor tempo.', '🃏', 'memoria', 'active', 'memoria',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 6, 'crystals', 3), jsonb_build_object('min_score', 4, 'crystals', 2)),
      'difficulty', 1, 'duration_seconds', 120,
      'engine_config', jsonb_build_object('pairs', 6, 'columns', 4, 'emojis', jsonb_build_array('🎮','🎧','🎬','⚽','🚀','⭐'))
    ), 6, 4),

  ('pares', 'Pares Mágicos', 'Combine 8 pares de cartas mágicas.', '🪄', 'memoria', 'active', 'memoria',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 8, 'crystals', 3), jsonb_build_object('min_score', 5, 'crystals', 2)),
      'difficulty', 2, 'duration_seconds', 150,
      'engine_config', jsonb_build_object('pairs', 8, 'columns', 4, 'emojis', jsonb_build_array('🐉','🦄','🌙','⭐','🔥','💎','🏰','⚔️'))
    ), 8, 22),

  ('quebra', 'Quebra-Peças', 'Combine as peças que formam o mesmo par.', '🧩', 'quebra-cabeca', 'active', 'memoria',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 6, 'crystals', 2), jsonb_build_object('min_score', 4, 'crystals', 1)),
      'difficulty', 1, 'duration_seconds', 100,
      'engine_config', jsonb_build_object('pairs', 6, 'columns', 4, 'emojis', jsonb_build_array('🔴','🟠','🟡','🟢','🔵','🟣'))
    ), 6, 23),

  ('cartas', 'Pares de Cartas', 'Encontre todos os pares de cartas do baralho.', '🃏', 'cartas', 'active', 'memoria',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 10, 'crystals', 4), jsonb_build_object('min_score', 6, 'crystals', 2)),
      'difficulty', 3, 'duration_seconds', 180,
      'engine_config', jsonb_build_object('pairs', 10, 'columns', 5, 'emojis', jsonb_build_array('A♠','K♠','Q♠','J♠','10♠','A♥','K♥','Q♥','J♥','10♥'))
    ), 10, 24),

  -- Matemática (engine matematica)
  ('mat', 'Contas Rápidas', 'Resolva contas de adição e subtração no tempo.', '🔢', 'matematica', 'active', 'matematica',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 9, 'crystals', 3), jsonb_build_object('min_score', 6, 'crystals', 2)),
      'difficulty', 1, 'duration_seconds', 100,
      'engine_config', jsonb_build_object('rounds', 10, 'ops', jsonb_build_array('+','-'), 'digit', 1, 'tint', '#8B5CF6')
    ), 10, 31),

  ('torre', 'Torre de Blocos', 'Some os blocos da construção e acerte o total.', '🏗️', 'construcao', 'active', 'matematica',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 7, 'crystals', 2), jsonb_build_object('min_score', 4, 'crystals', 1)),
      'difficulty', 1, 'duration_seconds', 90,
      'engine_config', jsonb_build_object('rounds', 8, 'ops', jsonb_build_array('+'), 'digit', 1, 'tint', '#F59E0B')
    ), 8, 33),

  -- Palavras (engine palavras)
  ('palavras', 'Palavra Embaralhada', 'Reordene as letras e forme a palavra correta.', '🔤', 'palavras', 'active', 'palavras',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 7, 'crystals', 3), jsonb_build_object('min_score', 4, 'crystals', 2)),
      'difficulty', 1, 'duration_seconds', 120,
      'engine_config', jsonb_build_object('mode', 'unscramble', 'rounds', 8, 'words', jsonb_build_array('JOGO','LIVE','KLAY','MÚSICA','BRASIL','ESTRELA','AMIGO','VÍDEO'))
    ), 8, 41),

  ('caça', 'Caça Palavras', 'Descubra a palavra correta pela dica dada.', '🔍', 'palavras', 'active', 'palavras',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 7, 'crystals', 3), jsonb_build_object('min_score', 4, 'crystals', 2)),
      'difficulty', 2, 'duration_seconds', 120,
      'engine_config', jsonb_build_object('mode', 'definition', 'rounds', 8, 'words', jsonb_build_array(
        jsonb_build_array('Grande felino selvagem', 'LEÃO', 'CACHORRO', 'GATO'),
        jsonb_build_array('Fruta tropical amarela', 'MAÇÃ', 'BANANA', 'UVA'),
        jsonb_build_array('Nome dado à televisão', 'RÁDIO', 'TV', 'CINEMA'),
        jsonb_build_array('Usamos para escrever', 'LÁPIS', 'MESA', 'CADEIRA'),
        jsonb_build_array('Meio de transporte aéreo', 'CARRO', 'BARCO', 'AVIÃO'),
        jsonb_build_array('Cor do céu limpo', 'VERDE', 'AZUL', 'PRETO'),
        jsonb_build_array('Aparelho que faz chamadas', 'CELULAR', 'RELOGIO', 'ESPELHO'),
        jsonb_build_array('Ingrediente do pão', 'FARINHA', 'SAL', 'AÇÚCAR')
      ))
    ), 8, 42),

  -- Arcade (engine arcade — desviar/coletar)
  ('acrobat', 'Acrobata', 'Desvie dos obstáculos por 30 segundos e pontue.', '🕹️', 'arcade', 'active', 'arcade',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 30, 'crystals', 3), jsonb_build_object('min_score', 18, 'crystals', 2)),
      'difficulty', 2, 'duration_seconds', 30, 'max_visible', 50,
      'engine_config', jsonb_build_object('duration_seconds', 30, 'speed', 1.0, 'tint', '#E4183C')
    ), 50, 51),

  ('goleiro', 'Goleiro', 'Desvie das bolas e salve os gols por 20 segundos.', '🥅', 'esportes', 'active', 'arcade',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 24, 'crystals', 3), jsonb_build_object('min_score', 14, 'crystals', 2)),
      'difficulty', 1, 'duration_seconds', 20, 'max_visible', 40,
      'engine_config', jsonb_build_object('duration_seconds', 20, 'speed', 1.1, 'tint', '#34D399', 'mover_left', 'Melhor saída!')
    ), 40, 52),

  ('floresta', 'Trilha na Floresta', 'Desvie das árvores e atravesse a floresta.', '🌲', 'aventura', 'active', 'arcade',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 28, 'crystals', 3), jsonb_build_object('min_score', 16, 'crystals', 2)),
      'difficulty', 2, 'duration_seconds', 25, 'max_visible', 45,
      'engine_config', jsonb_build_object('duration_seconds', 25, 'speed', 1.0, 'tint', '#34D399')
    ), 45, 53),

  -- Estratégia (engine estrategia — 3 em linha reutilizável)
  ('velha', 'Jogo da Velha', 'Vença a máquina no clássico jogo da velha (3x3).', '⭕', 'estrategia', 'active', 'estrategia',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 10, 'crystals', 3)),
      'difficulty', 1, 'duration_seconds', 120
    ), 10, 61),

  ('estrela', 'Estrela 3 em Linha', 'Forme 3 em linha antes da máquina.', '⭐', 'estrategia', 'active', 'estrategia',
    jsonb_build_object(
      'rewards', jsonb_build_array(jsonb_build_object('min_score', 10, 'crystals', 3), jsonb_build_object('min_score', 2, 'crystals', 1)),
      'difficulty', 2, 'duration_seconds', 120
    ), 10, 62)
on conflict (id) do update set
  name = excluded.name, description = excluded.description, emoji = excluded.emoji,
  category = excluded.category, status = excluded.status, engine = excluded.engine,
  rules = excluded.rules, max_score = excluded.max_score, sort_order = excluded.sort_order;

-- '2048' (já existente) permanece em "em breve" — segue sem engine fake.
update public.games set category = 'quebra-cabeca' where id = '2048';