package com.klayk.klay_k

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder

/**
 * Service em primeiro plano dedicado à captura de tela (compartilhamento de
 * tela durante lives de jogo).
 *
 * O Android 10+ (API 29+) exige que a MediaProjection seja obtida via o
 * seletor oficial do sistema (ACTION_MEDIA_PROJECTION) e, no Android 14+
 * (API 34+), o service do tipo `mediaProjection` DEVE estar em primeiro plano
 * ANTES de o app chamar `getMediaProjection()` — caso contrário o sistema
 * lança SecurityException.
 *
 * Fluxo principal (recomendado):
 *  1. O Dart solicita o consentimento de captura de tela única via
 *     `Hardware.requestCapturePermission` (flutter_webrtc/LiveKit abre o
 *     seletor oficial e guarda o token).
 *  2. Em seguida o Dart chama `startCaptureService`; este service sobe em
 *     primeiro plano com o tipo `mediaProjection` (o consentimento já foi
 *     concedido) — requisito obrigatório antes de `getMediaProjection()`.
 *  3. O LiveKit enfim publica a track de tela reutilizando o token.
 *
 * Um fluxo legado (ação ACTION_MEDIA_PROJECTION, portando resultCode + Intent
 * do seletor) é mantido para robustez em APIs < 34.
 *
 * A captura de frames em si (a track de vídeo da tela) fica por conta do
 * flutter_webrtc/LiveKit; este service apenas garante o requisito de sistema
 * e mantém a notificação em primeiro plano durante toda a transmissão.
 */
class ScreenCaptureService : Service() {

    private var projection: MediaProjection? = null
    private var projectionManager: MediaProjectionManager? = null

    private var startedForeground = false

    companion object {
        private const val NOTIFICATION_ID = 9001
        const val ACTION_MEDIA_PROJECTION = "com.klayk.klay_k.action.MEDIA_PROJECTION"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
    }

    override fun onCreate() {
        super.onCreate()
        projectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Fluxo legado: encaminha o token de MediaProjection quando o seletor
        // JÁ foi concedido (mantido para robustez em APIs < 34).
        if (intent?.action == ACTION_MEDIA_PROJECTION) {
            val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, -1)
            val resultData: Intent? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(EXTRA_RESULT_DATA)
                }
            if (resultData != null) {
                acquireProjection(resultCode, resultData)
                return START_STICKY
            }
        }

        // Início sem token (fluxo principal): o Dart já solicitou o
        // consentimento de captura (Hardware.requestCapturePermission) e em
        // seguida inicia este service. Sobe o foreground service do tipo
        // `mediaProjection` ANTES de o flutter_webrtc chamar getMediaProjection()
        // — requisito obrigatório no Android 14+ (API 34).
        startForegroundSafe()
        return START_STICKY
    }

    private fun acquireProjection(resultCode: Int, resultData: Intent) {
        val mgr = projectionManager ?: return
        try {
            projection = mgr.getMediaProjection(resultCode, resultData)
        } catch (_: Exception) {
            // Se o token não puder ser usado (ex.: já usado), segue sem ele;
            // o essencial aqui é manter o FGS mediaProjection ativo.
        }
        startForegroundSafe()
        projection?.let { p ->
            p.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    stopSelf()
                }
            }, null)
        }
    }

    private fun startForegroundSafe() {
        val notification = buildNotification()
        if (startedForeground) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Tenta iniciar com o tipo mediaProjection. No Android 14+ isso só
            // é aceito se o consentimento de captura JÁ foi concedido — o que o
            // nosso fluxo Dart garante (requestCapturePermission antes de
            // startCaptureService). Em falha, desce para um FGS comum.
            try {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
                )
                startedForeground = true
                return
            } catch (_: SecurityException) {
                // Consentimento ausente (raro): cai para o FGS simples abaixo.
            }
        }
        startForeground(NOTIFICATION_ID, notification)
        startedForeground = true
    }

    override fun onDestroy() {
        projection?.stop()
        projection = null
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val channelId = "klayk_screen_capture"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                channelId,
                "Captura de tela",
                NotificationManager.IMPORTANCE_LOW,
            )
            nm.createNotificationChannel(channel)
            return Notification.Builder(this, channelId)
                .setContentTitle("KLAY K")
                .setContentText("Compartilhando sua tela na live")
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .build()
        }
        return Notification.Builder(this)
            .setContentTitle("KLAY K")
            .setContentText("Compartilhando sua tela na live")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .build()
    }
}
