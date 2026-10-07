-- KLAY K - Expansão do catálogo de presentes (Step 4).
--
-- Adiciona o Dragão Mítico (raridade Mítico 🔥) e mais 7 presentes inéditos
-- distribuídos entre incomum/especial/raro/épico, seguindo inteiramente a
-- arquitetura existente (tabela `gifts` no banco + seeds idempotentes via
-- on conflict). Nenhum arquivo novo no APK: os efeitos reutilizam os presets
-- procedurais (sparkle/starfall/fireflight/cosmicgate/dragoncelestial).

-- Dragão Mítico + novos presentes (sort_order segue a numeração atual 1..24).
insert into public.gifts (id, name, category_id, rarity_id, credits, icon, glyph, animation_key, effects, description, sort_order, is_featured, is_exclusive, is_limited, is_tradable) values
  ('dragao-mitico', 'Dragão Mítico', 'dragoes', 'mitico', 22000, '🐲', 'DM', 'dragoncelestial', '{"color":"#FF7043","trail":"#FFAB91"}'::jsonb,
   'A lenda encarnada: um dragão forjado no fogo dos tempos antigos, que cruza a tela deixando um rastro ígneo mitológico. A raridade Máxima abaixo do Lendário.', 25, true, false, false, true),
  ('dragao-sombrio', 'Dragão Sombrio', 'dragoes', 'epico', 8000, '🐉', 'DS', 'cosmicgate', '{"color":"#4A148C","trail":"#7B1FA2"}'::jsonb,
   'O guardião da noite: um dragão que emerge do portal violeta das sombras.', 26, false, false, false, true),
  ('espada-celestial', 'Espada Celestial', 'magia', 'raro', 4500, '⚔️', 'EC', 'fireflight', '{"color":"#42A5F5","trail":"#B3E5FC"}'::jsonb,
   'Forjada na luz dos céus: atravessa a tela em um voo de chamas azuis.', 27, false, false, false, true),
  ('tigre-neon', 'Tigre Neon', 'natureza', 'especial', 1800, '🐯', 'TN', 'sparkle', '{"color":"#7C4DFF","trail":"#B388FF"}'::jsonb,
   'A fúria da selva banhada em neon violeta.', 28, false, false, false, true),
  ('caixa-misteriosa', 'Caixa Misteriosa', 'divertidos', 'incomum', 400, '🎁', 'CM', 'sparkle', '{"color":"#FFD54F","trail":"#FFF3B0"}'::jsonb,
   'Quem sabe o que tem dentro? Só abra se tiver coragem.', 29, false, false, false, true),
  ('hypercar-arh', 'Hypercar A.R.H', 'carros', 'epico', 8500, '🏎️', 'HA', 'fireflight', '{"color":"#FF3D00","trail":"#FF9E80"}'::jsonb,
   'Velocidade pura em forma de máquina: o bólido da coleção A.R.H TECH.', 30, false, true, false, true),
  ('foguete-galactico', 'Foguete Galáctico', 'aviacao', 'epico', 9500, '🚀', 'FG', 'starfall', '{"color":"#29B6F6","trail":"#81D4FA"}'::jsonb,
   'Decolagem rumo ao infinito com uma chuva de estrelas no rastro.', 31, false, false, false, true),
  ('medalhao-lunar', 'Medalhão Lunar', 'magia', 'raro', 3200, '🌕', 'ML', 'starfall', '{"color":"#B2EBF2","trail":"#E0F7FA"}'::jsonb,
   'Um talismã banhado pelo brilho da lua cheia.', 32, false, false, false, true)
on conflict (id) do update set
  name = excluded.name, category_id = excluded.category_id, rarity_id = excluded.rarity_id,
  credits = excluded.credits, icon = excluded.icon, animation_key = excluded.animation_key,
  description = excluded.description, is_featured = excluded.is_featured,
  is_exclusive = excluded.is_exclusive, is_limited = excluded.is_limited, is_tradable = excluded.is_tradable,
  updated_at = now();

-- Stats de uso inicial (0) para os novos presentes aparecerem nas listas
-- "populares/tendências" sem quebrar a ordenação nos primeiros momentos.
insert into public.gift_usage_stats (gift_id, sent_count) values
  ('dragao-mitico', 0),
  ('dragao-sombrio', 0),
  ('espada-celestial', 0),
  ('tigre-neon', 0),
  ('caixa-misteriosa', 0),
  ('hypercar-arh', 0),
  ('foguete-galactico', 0),
  ('medalhao-lunar', 0)
on conflict (gift_id) do nothing;