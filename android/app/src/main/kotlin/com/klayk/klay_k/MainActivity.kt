package com.klayk.klay_k

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Canal vivo da bolinha flutuante.
    private var overlayChannel: MethodChannel? = null

    // Canal de captura de tela (Dart → nativo e nativo → Dart).
    private var mediaProjectionChannel: MethodChannel? = null

    /**
     * Marcador NATIVO do startup.
     *
     * Existe só para diagnóstico: sem ele, uma morte do processo ANTES do Dart
     * começar (ContentProvider, Application, engine) não deixa nenhum rastro,
     * porque nada em Dart chegou a rodar. A linha é anexada a um arquivo de
     * texto e serve de prova para o relatório de abertura.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        markNative("N2-native.activity.onCreate")
        super.onCreate(savedInstanceState)
        markNative("N2b-native.activity.super_onCreate_ok")
    }

    private fun markNative(step: String) {
        try {
            val stamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
                .format(Date())
            val sdk = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Build.VERSION.SDK_INT.toString()
            } else {
                "preO"
            }
            // Append simples: PrintWriter(File, Boolean) não existe em Kotlin.
            val writer = FileWriter(File(filesDir, "klayk_native.log"), true)
            writer.write("$stamp | pid=${Process.myPid()} | $step | sdk=$sdk\n")
            writer.flush()
            writer.close()
        } catch (_: Throwable) {
            // Diagnóstico nunca pode derrubar o app.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        markNative("N3-native.configureFlutterEngine")
        super.configureFlutterEngine(flutterEngine)
        markNative("N4-native.configureFlutterEngine_ok")
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        mediaProjectionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "klayk/media_projection",
        )

        mediaProjectionChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startCaptureService" -> {
                    requestNotificationPermissionIfNeeded()
                    try {
                        startCaptureService()
                        result.success(true)
                    } catch (t: Throwable) {
                        // NÃO engole a falha: o Dart precisa saber que o
                        // foreground service (e a captura) não subiu para
                        // exibir o erro real ao usuário.
                        Log.w(TAG, "startCaptureService: falha ao iniciar o service", t)
                        result.error(
                            "start_capture_failed",
                            t.message ?: "Falha ao iniciar a captura de tela.",
                            null
                        )
                    }
                }

                "stopCaptureService" -> {
                    // Stop pedido pelo próprio app: o onDestroy não deve
                    // notificar o Dart de volta (evita falso "parou sozinho").
                    ScreenCaptureService.silenceNextStop = true
                    stopCaptureService()
                    result.success(null)
                }

                "openAppSystemSettings" -> {
                    // Abre a página de detalhes/configurações do app (usado
                    // pela tela de negação da captura: o usuário pode corrigir
                    // permissões de notificação/gerais e voltar).
                    openAppSystemSettings()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // Canal da bolinha da Live de Jogo.
        overlayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "klayk/live_game_overlay",
        )

        overlayChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startOverlayService()
                    result.success(null)
                }

                "stop" -> {
                    stopOverlayService()
                    result.success(null)
                }

                "setup" -> {
                    if (!canDrawOverlays()) {
                        result.error(
                            "overlay_permission_denied",
                            "Permissão de exibição sobre outros apps não concedida.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    result.success(null)
                }

                "setMic",
                "setPaused",
                "setVoiceBot",
                "hide",
                "restore" -> {
                    // Encaminha o estado ao service ativo.
                    LiveGameOverlayService.instance?.setFromDart(
                        call.method,
                        call.arguments
                    )

                    result.success(null)
                }

                "openOverlaySettings" -> {
                    openOverlaySettings()
                    result.success(null)
                }

                "bringToFront" -> {
                    bringAppToFront()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // Canal de jogos instalados: lista o que está no dispositivo e abre um
        // jogo/app pelo package name (fluxo "escolher jogo instalado → live").
        val gamesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "klayk/games",
        )

        gamesChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "listApps" -> {
                    try {
                        result.success(listInstalledApps())
                    } catch (t: Throwable) {
                        Log.w(TAG, "listApps: falha ao listar apps", t)
                        result.error(
                            "list_games_failed",
                            t.message ?: "Falha ao listar os jogos instalados.",
                            null
                        )
                    }
                }

                "launchPackage" -> {
                    val pkg = call.argument<String>("package")
                    if (pkg.isNullOrBlank()) {
                        result.error(
                            "invalid_package",
                            "Pacote vazio/inválido.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    result.success(launchPackage(pkg))
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Cria o canal de notificação do KLAY K (obrigatório no Android 8+).
     *
     * O id precisa ser EXATAMENTE `klay_k_notifications`: é o mesmo id enviado
     * no payload da Edge Function `send-push` e no
     * default_notification_channel_id do AndroidManifest. O app só registra o
     * token FCM depois de ter sido aberto ao menos uma vez, então o canal JÁ
     * existe quando o primeiro push chega.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channels = listOf(
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "KLAY K",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Atividades gerais do KLAY K"
                setShowBadge(true)
            },
            NotificationChannel(
                NOTIFICATION_CHANNEL_SYSTEM,
                "Sistema",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Avisos gerais do KLAY K"
                setShowBadge(true)
            },
            NotificationChannel(
                NOTIFICATION_CHANNEL_MESSAGES,
                "Mensagens",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Novas mensagens diretas"
                setShowBadge(true)
            },
            NotificationChannel(
                NOTIFICATION_CHANNEL_LIKES,
                "Curtidas",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Curtidas nos seus vídeos"
                setShowBadge(true)
            },
            NotificationChannel(
                NOTIFICATION_CHANNEL_COMMENTS,
                "Comentários",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Comentários e respostas"
                setShowBadge(true)
            },
            NotificationChannel(
                NOTIFICATION_CHANNEL_FOLLOWS,
                "Novos seguidores",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Novos seguidores"
                setShowBadge(true)
            },
            NotificationChannel(
                NOTIFICATION_CHANNEL_LIVE,
                "LIVE iniciado",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Lives iniciadas por creators"
                setShowBadge(true)
            },
            NotificationChannel(
                NOTIFICATION_CHANNEL_GIFTS,
                "Presentes",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Presentes enviados para você"
                setShowBadge(true)
            },
            NotificationChannel(
                NOTIFICATION_CHANNEL_MENTIONS,
                "Menções",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Menções em comentários"
                setShowBadge(true)
            }
        )
        channels.forEach { manager.createNotificationChannel(it) }
    }

    /**
     * Inicia o service de captura em primeiro plano.
     *
     * A captura de tela é responsabilidade do ScreenCaptureService.
     * A MainActivity não precisa permanecer viva durante a transmissão.
     */
    private fun startCaptureService() {
        requestNotificationPermissionIfNeeded()

        // Entrega o canal Flutter ao service para que ele possa avisar o Dart
        // quando for encerrado fora do fluxo normal do app.
        ScreenCaptureService.pendingFlutterChannel = mediaProjectionChannel

        val intent = Intent(
            this,
            ScreenCaptureService::class.java
        )

        startServiceCompat(intent)
    }

    /**
     * Para o service de captura.
     */
    private fun stopCaptureService() {
        val intent = Intent(
            this,
            ScreenCaptureService::class.java
        )

        stopService(intent)
    }

    /**
     * Abre a página de configurações do app no Android.
     *
     * A captura de tela (MediaProjection) não tem uma tela de configuração
     * própria: a permissão só pode ser concedida pelo seletor do Android. Esta
     * página de detalhes permite ao usuário corrigir permissões que possam
     * bloquear a transmissão (ex.: notificações no Android 13+ — necessárias
     * para o foreground service de projeção).
     */
    private fun openAppSystemSettings() {
        try {
            val intent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {
            try {
                startActivity(
                    Intent(Settings.ACTION_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (_: Exception) {
                // Ignora caso o dispositivo não disponibilize a tela.
            }
        }
    }

    /**
     * Inicia um service de forma compatível com diferentes versões do Android.
     */
    private fun startServiceCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    /**
     * Inicia a bolinha flutuante da Live de Jogo.
     */
    private fun startOverlayService() {
        if (!canDrawOverlays()) {
            return
        }

        requestNotificationPermissionIfNeeded()

        // Entrega o canal Flutter ao service.
        LiveGameOverlayService.pendingChannel = overlayChannel

        // Se o service de overlay JÁ está rodando (ex.: chamada repetida de
        // "start" vinda do Dart), apenas garante o canal — não re-inicia nem
        // re-adiciona a bolinha (evita views duplicadas e churn de sinistros).
        if (LiveGameOverlayService.instance != null) {
            return
        }

        val intent = Intent(
            this,
            LiveGameOverlayService::class.java
        )

        startServiceCompat(intent)
    }

    /**
     * Para a bolinha flutuante.
     */
    private fun stopOverlayService() {
        val intent = Intent(
            this,
            LiveGameOverlayService::class.java
        )

        stopService(intent)
    }

    /**
     * Abre as configurações de permissão de sobreposição.
     */
    private fun openOverlaySettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )

                startActivity(intent)
            } catch (_: Exception) {
                try {
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                    )
                } catch (_: Exception) {
                    // Ignora caso o dispositivo não disponibilize a tela.
                }
            }
        }
    }

    /**
     * Lista os apps/jogos com atividade de launcher instalados no dispositivo.
     *
     * Devolve uma lista de mapas `{package, label, icon}` — o ícone vem em
     * base64 PNG (~96px) para renderizar direto na grade do app. Na prática o
     * usuário escolhe o jogo instalado e toca para iniciar a Live de Jogo.
     *
     * No Android 11+ (API 30) a visibilidade de pacotes é restrita ao que o
     * manifest declara em `<queries>` (intent MAIN/LAUNCHER) — já declarado.
     */
    private fun listInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val result = mutableListOf<Map<String, Any>>()
        try {
            @Suppress("DEPRECATION")
            val resolved = pm.queryIntentActivities(intent, 0)
            for (ri in resolved) {
                val ai = ri.activityInfo ?: continue
                val pkg = ai.packageName ?: continue
                if (pkg == packageName) continue
                val label = runCatching {
                    ri.loadLabel(pm)?.toString()
                        ?: ai.loadLabel(pm)?.toString()
                }.getOrNull().orEmpty()
                if (label.isBlank()) continue
                val icon = runCatching {
                    val d = ai.loadIcon(pm) ?: return@runCatching ""
                    bitmapToIconBase64(drawableToBitmap(d))
                }.getOrNull().orEmpty()
                result.add(mapOf(
                    "package" to pkg,
                    "label" to label,
                    "icon" to icon,
                ))
            }
        } catch (_: Throwable) {
            // Listagem é best-effort: sem visibilidade o app segue sem a grade.
        }
        result.sortBy { (it["label"] as String).lowercase() }
        return result
    }

    /**
     * Abre um jogo/app pelo package name (intent de launcher). Retorna `true`
     * se conseguiu iniciar a atividade.
     */
    private fun launchPackage(pkg: String): Boolean {
        val pm = packageManager
        val intent = pm.getLaunchIntentForPackage(pkg) ?: return false
        return try {
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            )
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** Converte um Drawable (ícone de app) em Bitmap. */
    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        val bitmapDrawable = drawable as? BitmapDrawable
        val bmp = bitmapDrawable?.bitmap
        if (bmp != null) return bmp
        val width = drawable.intrinsicWidth.coerceAtLeast(1)
        val height = drawable.intrinsicHeight.coerceAtLeast(1)
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return out
    }

    /** Reduz o ícone para ~96px e codifica em base64 PNG (payload leve pro canal). */
    private fun bitmapToIconBase64(source: Bitmap): String {
        var icon = source
        if (icon.width > 96 || icon.height > 96) {
            val scale = 96f / maxOf(icon.width, icon.height)
            icon = Bitmap.createScaledBitmap(
                icon,
                (icon.width * scale).toInt().coerceAtLeast(1),
                (icon.height * scale).toInt().coerceAtLeast(1),
                true
            )
        }
        val out = ByteArrayOutputStream()
        icon.compress(Bitmap.CompressFormat.PNG, 100, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }

    /**
     * Traz o KLAY K para o primeiro plano.
     *
     * Usado pela bolinha quando o usuário quer voltar para o aplicativo
     * enquanto a live continua ativa.
     */
    private fun bringAppToFront() {
        try {
            val intent = Intent(
                this,
                MainActivity::class.java
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }

            startActivity(intent)
        } catch (_: Exception) {
            // Evita derrubar o processo caso a Activity não possa ser aberta.
        }
    }

    /**
     * Verifica se a permissão de sobreposição está concedida.
     */
    private fun canDrawOverlays(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(this)
    }

    /**
     * No Android 13+, solicita permissão para notificações.
     */
    private fun requestNotificationPermissionIfNeeded() {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATIONS_REQUEST_CODE,
            )
        }
    }

    companion object {
        private const val NOTIFICATIONS_REQUEST_CODE = 2001
        private const val TAG = "MainActivity"

        /** Canal de push do KLAY K (id igual ao payload da Edge Function). */
        private const val NOTIFICATION_CHANNEL_ID = "klay_k_notifications"
        private const val NOTIFICATION_CHANNEL_SYSTEM = "klay_k_system"
        private const val NOTIFICATION_CHANNEL_MESSAGES = "klay_k_messages"
        private const val NOTIFICATION_CHANNEL_LIKES = "klay_k_likes"
        private const val NOTIFICATION_CHANNEL_COMMENTS = "klay_k_comments"
        private const val NOTIFICATION_CHANNEL_FOLLOWS = "klay_k_follows"
        private const val NOTIFICATION_CHANNEL_LIVE = "klay_k_live"
        private const val NOTIFICATION_CHANNEL_GIFTS = "klay_k_gifts"
        private const val NOTIFICATION_CHANNEL_MENTIONS = "klay_k_mentions"
    }
}