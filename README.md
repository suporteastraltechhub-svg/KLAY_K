# KLAY K

Aplicativo KLAY K com sistema de **lives reais** integrado a
**Supabase** (auth, Postgres + Realtime, Edge Functions) e **LiveKit Cloud** (vídeo/áudio),
mais um bot assistente "KLAY K Bot" que roda no servidor.

> Segurança: o app recebe **apenas tokens temporários** do LiveKit. As chaves
> `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` existem **somente** nos Secrets das Edge
> Functions e no `.env` do serviço do bot — nunca no código do Flutter nem no Git.

## Arquitetura

```
App Flutter ──▶ Supabase (Auth + Postgres + Realtime) ──▶ Edge Functions ──▶ LiveKit Cloud ──▶ sala
                    └── chat/eventos/presentes/lives (banco)      │
                                                                   └── token temporário (server_url + participant_token)
Servidor ── "KLAY K Bot" (services/livekit-bot) ── reage a eventos e fala (TTS) na sala
```

- **Supabase** = usuários/auth, banco, chat, eventos, presentes, dados das lives.
- **LiveKit** = vídeo/áudio em tempo real, conexão, participantes, transmissão.
- O app já vem configurado por padrão com as credenciais **públicas** do projeto real
  (`SUPABASE_URL` + `SUPABASE_PUBLISHABLE_KEY` em `lib/services/app_config.dart`). Se o
  backend não estiver acessível, ele recai no **modo demo** (dados simulados) sem quebrar
  nada.

## Testar no app (desenvolvedor)

O app usa por padrão o projeto real embutido, então basta:

```bash
flutter run
```

Para apontar para outro projeto sem recompilar o código:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_SUA-CHAVE \
  --dart-define=SUPABASE_PROJECT_REF=SEU-REF
```

> `SUPABASE_ANON_KEY` (legado) ainda é aceito como fallback de `SUPABASE_PUBLISHABLE_KEY`.

## Configuração manual pendente (Supabase + LiveKit)

O projeto real `oysyuialaelzcxxkfdsl` já tem Auth (GoTrue), `profiles` e as tabelas
starter (`follows`, `likes`, `comments`). Faltam aplicar: (1) ativar login anônimo,
(2) aplicar a migration das tabelas de live, (3) deploy das Edge Functions + Secrets,
(4) webhook do LiveKit e (5) rodar o bot.

1. **Ative o login anônimo** no painel do Supabase: **Authentication → Sign In /
   Providers → Anonymous sign-ins** (o KLAY K cria a sessão sozinho para assistir).
   Sem isso o app mostra o aviso e segue em modo demo.
2. Aplique as migrations do repositório (em ordem):
   - `supabase/migrations/20260827000000_init.sql` — cria/ajusta `lives`,
     `live_participants`, `live_chat`, `live_gifts`, `live_events` + RLS + políticas
     (idempotente e compatível com o `profiles` já existente no projeto).
   - `supabase/migrations/20260828000000_fix_follows.sql` — corrige a tabela
     `follows` existente (adiciona `id` como PK, índices, unicidade e RLS) **sem
     descartar dados**.
   ```bash
   supabase db push   # aplica as migrations no projeto vinculado
   ```
3. Configure os Secrets no painel do Supabase (**Project Settings → Edge Functions →
   Secrets**):

   | Secret | Para que serve |
   | --- | --- |
   | `LIVEKIT_URL` | URL do servidor LiveKit (ex.: `wss://...cloud`) |
   | `LIVEKIT_API_KEY` | API key do LiveKit |
   | `LIVEKIT_API_SECRET` | API secret do LiveKit (**nunca** no app) |

   (`SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` são injetados automaticamente.)
4. Faça o deploy das Edge Functions:
   ```bash
   supabase functions deploy livekit-token create-live end-live livekit-webhook
   ```
   Elas estão em `supabase/functions/` (o `config.toml` define `verify_jwt = true`
   para `livekit-token`; `create-live`/`end-live` validam o JWT manualmente;
   `livekit-webhook` fica `verify_jwt = false` e autentica por **HMAC**
   (`x-livekit-signature`) — nunca por JWT de usuário).
5. Configure o webhook do LiveKit para chamar `livekit-webhook` (os eventos
   `room_started`, `room_finished`, `participant_joined`, `participant_left`
   alimentam o histórico).
6. Rode o bot (veja abaixo).

## Deploy completo via Supabase CLI (passo a passo)

Pré-requisitos: [Supabase CLI](https://supabase.com/docs/guides/cli) instalado
(`supabase --version`). Neste projeto ele também pode ser instalado via:
`npm install -g supabase`.

1. **Login no Supabase** (gera um Personal Access Token em
   https://supabase.com/dashboard/account/tokens):
   ```bash
   supabase login
   # ou sem abrir navegador:
   supabase login --no-browser
   # ou com o token já existente:
   supabase login --token sbp_SEU_TOKEN
   ```
   Confirme com `supabase projects list`.

2. **Link do projeto** (a partir da raiz do repositório, que contém a pasta
   `supabase/`):
   ```bash
   cd /storage/internal_new/project/klay_k
   supabase link --project-ref oysyuialaelzcxxkfdsl
   ```
   Opcional: `supabase config push` para propagar `config.toml`
   (inclui `verify_jwt = true` do `livekit-token` etc.) para o projeto remoto.

3. **Secrets do LiveKit** (NUNCA no código/APK — apenas aqui):
   ```bash
   supabase secrets set --project-ref oysyuialaelzcxxkfdsl \
     LIVEKIT_URL=wss://SEU-PROJETO.livekit.cloud \
     LIVEKIT_API_KEY=NO_SEU_PAINEL_LIVEKIT \
     LIVEKIT_API_SECRET=NO_SEU_PAINEL_LIVEKIT
   ```
   Confirme com `supabase secrets list --project-ref oysyuialaelzcxxkfdsl`
   (os valores aparecem mascarados; os **nomes** `LIVEKIT_URL`, `LIVEKIT_API_KEY`,
   `LIVEKIT_API_SECRET` precisam existir).

4. **Ative o login anônimo** (necessário para o app criar sessão sozinho):
   Painel → **Authentication → Sign In / Providers → Anonymous sign-ins → enable**.

5. **Aplique as migrations em ordem** (idempotentes; seguro repetir):
   ```bash
   supabase db push
   # aplica supabase/migrations/*.sql no projeto vinculado
   # Para conferir antes: supabase db push --dry-run
   ```

6. **Deploy das 4 Edge Functions** (uma única chamada deploya todas):
   ```bash
   supabase functions deploy livekit-token create-live end-live livekit-webhook
   ```

7. **Webhook do LiveKit**: no painel do LiveKit Cloud →
   **Webhooks → Add Webhook** → URL:
   ```
   https://oysyuialaelzcxxkfdsl.supabase.co/functions/v1/livekit-webhook
   ```
   Eventos: `room_started`, `room_finished`, `participant_joined`,
   `participant_left`.

8. **Verificação**:
   ```bash
   # Functions no ar:
   supabase functions list --project-ref oysyuialaelzcxxkfdsl
   # Health do projeto:
   #   https://oysyuialaelzcxxkfdsl.supabase.co/auth/v1/health  (GET)
   # livekit-token sem auth deve retornar 401 (protegido):
   #   POST https://oysyuialaelzcxxkfdsl.supabase.co/functions/v1/livekit-token
   #   com body {"roomName":"probe"} → {"error":"unauthorized",401}
   # Tabelas criadas (PostgREST com a publishable key):
   #   GET .../rest/v1/lives?select=id&limit=1  → 200 []
   #   GET .../rest/v1/live_events?select=id&limit=1 → 200 []
   #   GET .../rest/v1/follows?select=id&limit=1 → 200 [] (agora com coluna id)
   ```
   Logs das Functions: Painel → **Edge Functions → {função} → Logs** (ou
   `supabase functions logs`).

## Bot ("KLAY K Bot")

Serviço Node/TypeScript em `services/livekit-bot/`. Entra nas salas como participante
"bot", reage a eventos (chat, gifts, entradas, follow, live start/end) com falas PT-BR
e cooldown por prioridade para não fazer spam; pode publicar áudio real (TTS OpenAI) se
habilitado.

```bash
cd services/livekit-bot
npm install
cp .env.example .env   # preencha as variáveis abaixo
npm run build          # checagem de tipos
npm test               # 22 testes unitários
npm start              # monitora salas e lives
```

Variáveis do `.env`:

| Variável | Obrigatória | Descrição |
| --- | --- | --- |
| `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` | sim | credenciais do LiveKit (escapam do app) |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | opcional | usar a service role para ler eventos |
| `BOT_TTS_PROVIDER` | opcional | `openai` ou `none` (padrão: falas só como texto) |
| `OPENAI_API_KEY` | opcional | TTS |
| `BOT_PUBLISH_AUDIO` | opcional (`true`) | publicar o áudio do TTS na sala |
| `BOT_MONITOR_ROOMS` | opcional | aceitar/ignorar salas (regex) |
| `BOT_NAME` | opcional | nome do bot na sala |

## Como testar uma live ponta a ponta

1. Rode o app (sem `--dart-define` já usa o projeto real embutido):
2. Toque no **"+"** na navegação inferior → **Live ao vivo** → preencha Título/
   Categoria/Hashtags/Descrição → **Iniciar Live** (câmera + mic são solicitados).
3. Em outro dispositivo/emulador, abra a aba **Live** → o card da transmissão aparece →
   assista. Comente no chat, envie presentes, dê like, siga, compartilhe.
4. O bot reage às falas/eventos na sala (se rodando).
5. O streamer toca em **Encerrar** (ou o menu de topo) para finalizar; espectadores são
   avisados e a live sai da lista.

## Testes do app

```bash
flutter analyze   # 0 issues
flutter test      # inclui modelos, menu "+", segredos ausentes no código
```

`test/live_integration_test.dart` também varre `lib/`, `supabase/` e `services/livekit-bot/`
e falha se algum valor de `sk_live_*`/JWT/secrets de serviço for encontrado no código.