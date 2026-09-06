package com.klayk.klay_k

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Canal vivo da bolinha flutuante.
    private var overlayChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "klayk/media_projection",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCaptureService" -> {
                    requestNotificationPermissionIfNeeded()
                    startCaptureService()
                    result.success(true)
                }

                "stopCaptureService" -> {
                    stopCaptureService()
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
    }

    /**
     * Inicia o service de captura em primeiro plano.
     *
     * A captura de tela é responsabilidade do ScreenCaptureService.
     * A MainActivity não precisa permanecer viva durante a transmissão.
     */
    private fun startCaptureService() {
        requestNotificationPermissionIfNeeded()

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
    }
}