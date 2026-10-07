import { createClient } from "npm:@supabase/supabase-js@^2";
import { JWT } from "npm:google-auth-library@^9";
import { json, opts } from "../_shared/cors.ts";

/**
 * KLAY K — Send-Push (canal de entrega FCM para Android)
 * ----------------------------------------------------------------------------
 * Supabase segue sendo o backend e a fonte da verdade: eventos REAIS gravam
 * uma linha em `notifications`; o trigger `push_notification_on_insert` chama
 * esta função (via pg_net, com o segredo de webhook) para entregar via FCM —
 * apenas transporte. O app nunca acessa esta função nem conhece qualquer
 * credencial administrativa.
 *
 * Segurança:
 *  - Exige o segredo de webhook (PUSH_WEBHOOK_SECRET) — somente o próprio
 *    servidor o envia; o cliente não sabe este segredo.
 *  - Recebe apenas `notification_id` (nunca destinatário/título arbitrários).
 *  - Re-fetches a notificação com service role (valida o evento real).
 *  - Respeita preferências (push_enabled + categoria) e bloqueios.
 *  - Remove tokens inválidos devolvidos pelo FCM.
 *  - Usa FCM HTTP v1 (OAuth via service account nas Secrets do Supabase).
 */

interface NotificationRow {
  id: string;
  user_id: string;
  actor_id: string | null;
  type: string;
  ref_id: string | null;
  message: string;
}

interface FcmMessage {
  message: {
    token: string;
    notification: { title: string; body: string };
    data: Record<string, string>;
    android: {
      priority: "HIGH";
      notification: {
        channel_id: string;
        default_sound: boolean;
        notification_priority: "PRIORITY_HIGH";
      };
    };
  };
}

function env(name: string): string | undefined {
  return Deno.env.get(name);
}

function secureEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Cria cliente OAuth 2.0 a partir da service account (Firebase) do secret. */
function buildFcmClient(): { jwt: JWT; projectId: string } | null {
  const raw = env("FCM_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    const clientEmail = parsed.client_email;
    const privateKey = parsed.private_key;
    const projectId = env("FCM_PROJECT_ID") || parsed.project_id;
    if (!clientEmail || !privateKey || !projectId) return null;
    const jwt = new JWT({
      email: clientEmail,
      key: privateKey,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    return { jwt, projectId };
  } catch (_) {
    return null;
  }
}

/**
 * Envia via FCM HTTP v1.
 * Retorna "ok" | "invalid_token" | "error".
 */
async function sendToFcm(
  token: string,
  client: JWT,
  projectId: string,
  title: string,
  body: string,
  data: Record<string, string>,
  channelId: string,
): Promise<string> {
  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const payload: FcmMessage = {
    message: {
      token,
      notification: { title, body },
      data,
      android: {
        priority: "HIGH",
        notification: {
          channel_id: channelId,
          default_sound: true,
          notification_priority: "PRIORITY_HIGH",
        },
      },
    },
  };
  try {
    const accessToken = await client.getAccessToken();
    if (!accessToken || !accessToken.token) return "error";
    const res = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    if (res.status === 404) return "invalid_token";
    if (res.status === 400) {
      const bodyText = await res.text();
      if (bodyText.includes("UNREGISTERED") ||
          bodyText.includes("not-a-registered-token") ||
          bodyText.includes("registration-token-not-registered")) {
        return "invalid_token";
      }
      return "error";
    }
    if (!res.ok) return "error";
    return "ok";
  } catch (_) {
    return "error"; // rede/FCM indisponível — o trigger não reenvia (idempotente)
  }
}

function notificationBody(
  type: string,
  message: string,
  actorDisplay: string | null,
): string {
  const whom = actorDisplay ? `@${actorDisplay}` : "Alguém";
  switch (type) {
    case "like":
      return `${whom} curtiu seu vídeo`;
    case "comment":
      return `${whom} comentou no seu vídeo`;
    case "comment_reply":
      return `${whom} respondeu seu comentário`;
    case "mention":
      return `${whom} mencionou você em um comentário`;
    case "share":
      return `${whom} compartilhou seu vídeo`;
    case "follow":
      return `Você ganhou um novo seguidor: ${whom}`;
    case "message":
      return message.trim().length === 0
        ? "Você recebeu uma nova mensagem"
        : `Mensagem de ${whom}: ${message}`;
    case "live":
      return `${whom} iniciou uma Live. Toque para assistir.`;
    case "gift":
    case "gift_send":
    case "gift_sent":
      return `${whom} te enviou um presente`;
    default:
      return "Nova atividade no KLAY K";
  }
}

function notificationChannel(type: string): string {
  switch (type) {
    case "message":
      return "klay_k_messages";
    case "like":
      return "klay_k_likes";
    case "comment":
    case "comment_reply":
    case "share":
      return "klay_k_comments";
    case "follow":
      return "klay_k_follows";
    case "live":
      return "klay_k_live";
    case "gift":
    case "gift_send":
    case "gift_sent":
      return "klay_k_gifts";
    case "mention":
      return "klay_k_mentions";
    default:
      return "klay_k_system";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return opts();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const expectedSecret = env("PUSH_WEBHOOK_SECRET");
  const authHeader = req.headers.get("authorization") ?? "";
  if (!expectedSecret ||
      !authHeader.startsWith("Bearer ") ||
      !secureEqual(authHeader.slice("Bearer ".length).trim(), expectedSecret)) {
    return json({ error: "forbidden" }, 403);
  }

  let body: { notification_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const notificationId = body?.notification_id;
  if (typeof notificationId !== "string" || notificationId.length < 8) {
    return json({ error: "notification_id_required" }, 400);
  }

  const svc = createClient(
    env("SUPABASE_URL") as string,
    env("SUPABASE_SERVICE_ROLE_KEY") as string,
    { auth: { persistSession: false } },
  );

  // Valida o evento REAL: carrega a notificação pelo id (existe = evento real).
  const { data: notif, error: notifErr } = await svc
    .from("notifications")
    .select(
      "id,user_id,actor_id,type,ref_id,message,actor:actor_id(display_name,username)",
    )
    .eq("id", notificationId)
    .maybeSingle();

  if (notifErr || !notif) {
    return json({ ok: false, reason: "notification_not_found" }, 200);
  }
  const row = notif as unknown as NotificationRow & {
    actor?: { display_name?: string | null; username?: string | null } | null;
  };

  // Tipos que não enviamos push (reforço do filtro do trigger).
  if (["record", "reward", "live_end", "live_viewer", "verification", "sale"]
      .includes(row.type)) {
    return json({ ok: true, reason: "type_not_pushable" }, 200);
  }

  // Self-notificação não vira push (você não se curte nem se segue).
  if (row.actor_id && row.actor_id === row.user_id) {
    return json({ ok: true, reason: "self" }, 200);
  }

  // Bloqueio: se o destinatário bloqueou o ator, não envia push.
  if (row.actor_id) {
    const { data: blocked } = await svc
      .from("blocked_users")
      .select("id")
      .eq("blocker_id", row.user_id)
      .eq("blocked_id", row.actor_id)
      .maybeSingle();
    if (blocked) {
      return json({ ok: true, reason: "blocked" }, 200);
    }
  }

  // Preferências do destinatário.
  //
  // A lógica mora em `public.notification_allowed()` (migration
  // 20260928120000) para haver UMA fonte de verdade. Antes ela era um switch
  // solto aqui dentro, com duas consequências erradas:
  //   * 'comment_reply' e 'mention' caíam em `comments`, então não dava para
  //     desligar só menções ou só respostas;
  //   * 'gift' caía no `default` e era SEMPRE enviado, ignorando a preferência.
  // Se a função ainda não existir no banco (migration não aplicada), caímos
  // no `prefs` local abaixo, que é o comportamento antigo.
  let allowed = true;
  const { data: allowedRow, error: allowedErr } = await svc
    .rpc("notification_allowed", {
      p_user_id: row.user_id,
      p_type: row.type,
    })
    .maybeSingle();

  if (allowedErr) {
    // Função ausente no servidor: usa a leitura direta como fallback.
    const { data: prefs } = await svc
      .from("notification_preferences")
      .select(
        "likes,comments,replies,mentions,follows,messages,live,gifts,news,push_enabled",
      )
      .eq("user_id", row.user_id)
      .maybeSingle();

    if (prefs) {
      const p = prefs as Record<string, boolean | undefined>;
      if (p.push_enabled === false) {
        allowed = false;
      } else {
        switch (row.type) {
          case "like":
            allowed = p.likes !== false;
            break;
          case "comment":
          case "share":
            allowed = p.comments !== false;
            break;
          case "comment_reply":
            allowed = p.replies !== false;
            break;
          case "mention":
            allowed = p.mentions !== false;
            break;
          case "follow":
            allowed = p.follows !== false;
            break;
          case "message":
            allowed = p.messages !== false;
            break;
          case "live":
            allowed = p.live !== false;
            break;
          case "gift":
          case "gift_send":
          case "gift_sent":
            allowed = p.gifts !== false;
            break;
          case "news":
            allowed = p.news !== false;
            break;
          default:
            allowed = true;
        }
      }
    }
  } else if (typeof allowedRow === "boolean") {
    allowed = allowedRow;
  }
  if (!allowed) {
    return json({ ok: true, reason: "prefs" }, 200);
  }

  // Tokens Android do destinatário.
  const { data: tokens } = await svc
    .from("push_tokens")
    .select("token")
    .eq("user_id", row.user_id)
    .eq("platform", "android");
  const userTokens = (tokens ?? []) as Array<{ token: string }>;
  if (userTokens.length === 0) {
    return json({ ok: true, reason: "no_tokens" }, 200);
  }

  const fcm = buildFcmClient();
  if (!fcm) {
    return json({ ok: false, reason: "fcm_not_configured" }, 503);
  }

  const actorDisplay = row.actor?.username || row.actor?.display_name || null;
  const title = "KLAY K";
  const body = notificationBody(row.type, row.message, actorDisplay);
  const channelId = notificationChannel(row.type);
  const data: Record<string, string> = {
    klayk_id: row.id,
    klayk_type: row.type,
    klayk_ref: row.ref_id ?? "",
    klayk_actor: row.actor_id ?? "",
    klayk_recipient: row.user_id,
  };

  let invalidRemoved = 0;
  for (const t of userTokens) {
    const res = await sendToFcm(
      t.token,
      fcm.jwt,
      fcm.projectId,
      title,
      body,
      data,
      channelId,
    );
    if (res === "invalid_token") {
      invalidRemoved++;
      await svc.from("push_tokens").delete().eq("token", t.token);
    }
  }

  return json({
    ok: true,
    sent: true,
    invalidRemoved,
    project: fcm.projectId,
  });
});