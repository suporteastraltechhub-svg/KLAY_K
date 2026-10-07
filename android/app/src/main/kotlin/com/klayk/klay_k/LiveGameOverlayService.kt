package com.klayk.klay_k

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel

/**
 * Bolinha flutuante profissional da Live de Jogo do KLAY K.
 *
 * Aparece sobre outros aplicativos (SYSTEM_ALERT_WINDOW) enquanto o streamer
 * transmite gameplay. É arrastável e abre um painel de controles com:
 *   - Mic (ligar/desligar)
 *   - Pausar/retomar a transmissão
 *   - Ocultar a bolinha (sem encerrar a live; restaurada via notificação)
 *   - Encerrar a live (com confirmação)
 *   - Bot de voz (ativar/desativar)
 *   - Mais opções (configurações, qualidade, chat)
 *
 * Cada ação chamada volta para o Dart via MethodChannel
 * ("klayk/live_game_overlay") para que o LiveKit seja de fato controlado.
 */
class LiveGameOverlayService : Service() {

    private val handler = Handler(Looper.getMainLooper())

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var panelView: View? = null
    private var hiddenIndicatorView: View? = null

    private var bubbleCollapsedX = 24
    private var bubbleCollapsedY = 320

    // Dimensões atuais da tela (recalculadas em onConfigurationChanged).
    private var screenWidth = 0
    private var screenHeight = 0

    // Áreas seguras do display (status bar, navigation bar, cutout) em pixels.
    // A bolinha/indicador/painel nunca podem entrar nessas regiões.
    private var safeTop = 0
    private var safeBottom = 0
    private var safeLeft = 0
    private var safeRight = 0

    // Estado refletido pelo painel (espelha o que o Flutter informa).
    @Volatile
    private var micEnabled = true
    @Volatile
    private var paused = false
    @Volatile
    private var voiceBotEnabled = false
    @Volatile
    private var hidden = false

    private var channel: MethodChannel? = null

    companion object {
        private const val TAG = "KLAYK_OVERLAY"
        private const val NOTIFICATION_ID = 9002
        private const val CHANNEL_ID = "klayk_live_game_overlay"

        /** Dimensão da janela da bolinha (dp) — área de toque/arrastar. */
        private const val BUBBLE_SIZE_DP = 64
        /** Diâmetro do círculo visível (dentro da janela, com espaço p/ o halo). */
        private const val BUBBLE_CIRCLE_DP = 52
        /** Botões menores do painel compacto (grade 2×4). */
        private const val CHIP_WIDTH_DP = 52
        private const val CHIP_HEIGHT_DP = 46

        // Paleta neon da bolinha (identidade KLAY K).
        private val COLOR_NEON_BORDER = 0xFFB794FF.toInt()
        private val COLOR_NEON_GLOW = 0xFF8B5CF6.toInt()
        private val COLOR_LIVE_DOT = 0xFFFF2E4D.toInt()
        // Halo do brilho (preset com transparência já embutida).
        private val GLOW_STRONG = 0x4D8B5CF6.toInt()

        const val ACTION_START = "start"
        const val ACTION_HIDE = "hide"
        const val ACTION_RESTORE = "restore"
        const val ACTION_STOP = "stop"

        /** Instância ativa deste service (set em onCreate, limpa em onDestroy).
         *  Usada pela MainActivity para encaminhar estado do painel ao service
         *  realmente rodando. */
        @Volatile
        var instance: LiveGameOverlayService? = null

        /** Canal do Flutter pelo qual o painel notifica o Dart. É setado pela
         *  MainActivity ANTES de iniciar o service, e também em [setupChannel]. */
        @Volatile
        var pendingChannel: MethodChannel? = null

        /** Envia um evento para o Dart sem precisar de instância. */
        fun notifyAction(name: String, payload: Any? = null) {
            pendingChannel?.invokeMethod(name, payload)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate: service criado")
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        updateScreenSize()
        refreshSafeInsets()
        // Posição inicial da bolinha: canto direito, abaixo da status bar.
        bubbleCollapsedX = dp(24)
        bubbleCollapsedY = safeTop + dp(180)
        clampBubbleToBounds()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Mantém a posição da bolinha dentro da nova área após rotação.
        updateScreenSize()
        refreshSafeInsets()
        clampBubbleToBounds()
        bubbleView?.let { v ->
            val params = bubbleLayoutParams()
            params.x = bubbleCollapsedX
            params.y = bubbleCollapsedY
            try { windowManager?.updateViewLayout(v, params) } catch (_: Exception) {}
        }
        repositionHiddenIndicator()
    }

    private fun updateScreenSize() {
        val metrics = resources.displayMetrics
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
    }

    /** Mede as áreas seguras do sistema para o OVERLAY (coordenada da tela
     *  inteira, consistente com FLAG_LAYOUT_NO_LIMITS): status bar, navigation
     *  bar e cutout. API 30+ usa [WindowManager.currentWindowMetrics]; antes,
     *  cai para dimensões de recurso do sistema. */
    private fun refreshSafeInsets() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val wm = windowManager ?: return
            val metrics = wm.currentWindowMetrics
            val insets = metrics.windowInsets.getInsets(
                android.view.WindowInsets.Type.systemBars() or
                    android.view.WindowInsets.Type.displayCutout()
            )
            safeTop = insets.top
            safeBottom = insets.bottom
            safeLeft = insets.left
            safeRight = insets.right
        } else {
            safeTop = systemBarDimen("status_bar_height")
            safeBottom = navBarHeightCompat()
            safeLeft = 0
            safeRight = 0
        }
    }

    private fun systemBarDimen(id: String): Int {
        val identifier =
            resources.getIdentifier(id, "dimen", "android")
        return if (identifier > 0) resources.getDimensionPixelSize(identifier) else 0
    }

    private fun navBarHeightCompat(): Int {
        val landscape =
            resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val id = if (landscape) "navigation_bar_height_landscape" else "navigation_bar_height"
        var h = systemBarDimen(id)
        if (h == 0) h = systemBarDimen("navigation_bar_height")
        return h
    }

    private fun safeMargin(): Int = dp(4)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handleIntent(intent)
        return START_STICKY
    }

    private fun handleIntent(intent: Intent?) {
        when (intent?.action) {
            ACTION_START, null -> {
                showForegroundNotification()
                if (hidden) showHiddenIndicator() else showBubble()
            }
            ACTION_HIDE -> setHidden(true)
            ACTION_RESTORE -> setHidden(false)
            ACTION_STOP -> { stopSelf() }
        }
    }

    // -------------------------------------------------------------------------
    // Configuração do canal Dart (método + callbacks de estado)
    // -------------------------------------------------------------------------

    /** Liga o canal do Flutter ao service. Chamado pela MainActivity com o canal
     *  que ela já possui, permitindo que [notifyAction] alcance o Dart. */
    fun setupChannel(methodChannel: MethodChannel) {
        channel = methodChannel
        pendingChannel = methodChannel
    }

    /** Aplica um comando/estado vindo do Dart na instância ativa do service.
     *  Chamado pela MainActivity (que é dona do canal). */
    fun setFromDart(method: String, arguments: Any?) {
        @Suppress("UNCHECKED_CAST")
        fun argBool(name: String, def: Boolean): Boolean =
            (arguments as? Map<*, *>)?.get(name) as? Boolean ?: def
        when (method) {
            "setMic" -> {
                micEnabled = argBool("enabled", true)
                refreshControls()
            }
            "setPaused" -> {
                paused = argBool("paused", false)
                refreshControls()
            }
            "setVoiceBot" -> {
                voiceBotEnabled = argBool("enabled", false)
                refreshControls()
            }
            "hide" -> setHidden(true)
            "restore" -> setHidden(false)
            "stop" -> stopSelf()
        }
    }

    // -------------------------------------------------------------------------
    // Foreground notification (permite restaurar a bolinha / encerrar)
    // -------------------------------------------------------------------------

    @SuppressLint("NotificationPermission")
    private fun showForegroundNotification() {
        val channelId = CHANNEL_ID
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                channelId,
                "Live de Jogo",
                NotificationManager.IMPORTANCE_LOW,
            )
            nm.createNotificationChannel(channel)

            val stopIntent = Intent(this, LiveGameOverlayService::class.java).apply {
                action = ACTION_STOP
            }
            val stopPi = android.app.PendingIntent.getService(
                this, 1, stopIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE
            )

            val restoreIntent = Intent(this, LiveGameOverlayService::class.java).apply {
                action = ACTION_RESTORE
            }
            val restorePi = android.app.PendingIntent.getService(
                this, 2, restoreIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE
            )

            val contentText =
                if (paused) "Transmissão pausada — toque para retomar"
                else "Você está transmitindo sua tela ao vivo"
            val notification = Notification.Builder(this, channelId)
                .setContentTitle("🎮 Live de Jogo")
                .setContentText(contentText)
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setContentIntent(restorePi)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Encerrar", stopPi)
                .build()

            try {
                startForeground(NOTIFICATION_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } catch (t: Throwable) {
                Log.e(TAG, "showForegroundNotification: FGS especial falhou — caindo para simples", t)
                try {
                    startForeground(NOTIFICATION_ID, notification)
                } catch (t2: Throwable) {
                    Log.e(TAG, "showForegroundNotification: FGS simples também falhou", t2)
                }
            }
        } else {
            startForeground(NOTIFICATION_ID,
                Notification.Builder(this)
                    .setContentTitle("🎮 Live de Jogo")
                    .setContentText("Você está transmitindo sua tela ao vivo")
                    .setSmallIcon(android.R.drawable.ic_menu_share)
                    .setOngoing(true)
                    .build())
        }
    }

    // -------------------------------------------------------------------------
    // Bolinha flutuante (arrastável)
    // -------------------------------------------------------------------------

    private fun showBubble() {
        removeViews()
        hidden = false
        val wm = windowManager ?: return
        val isOverlayGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(this)
        if (!isOverlayGranted) {
            Log.e(TAG, "showBubble: SYSTEM_ALERT_WINDOW não concedida — bolinha não exibida")
            return
        }

        val bubble = createBubbleView(wm)
        bubbleView = bubble
        try {
            wm.addView(bubble, bubbleLayoutParams())
            Log.i(TAG, "showBubble: bolinha ADICIONADA ao WindowManager (${bubbleLayoutParams().x},${bubbleLayoutParams().y})")
        } catch (t: Throwable) {
            Log.e(TAG, "showBubble: falha ao adicionar bolinha ao WindowManager", t)
            bubbleView = null
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createBubbleView(wm: WindowManager): View {
        val size = bubbleSize()
        val root = FrameLayout(this)
        root.clipChildren = false
        root.setBackgroundColor(android.graphics.Color.TRANSPARENT)

        // Halo de brilho neon difuso (suave e estático — sem efeitos de piscar).
        val glow = View(this)
        val glowBg = android.graphics.drawable.GradientDrawable()
        glowBg.shape = android.graphics.drawable.GradientDrawable.OVAL
        glowBg.gradientType = android.graphics.drawable.GradientDrawable.RADIAL_GRADIENT
        glowBg.setColors(intArrayOf(GLOW_STRONG, 0x148B5CF6.toInt(), 0x008B5CF6.toInt()))
        glowBg.setGradientRadius(size * 0.5f)
        glow.background = glowBg
        root.addView(glow, FrameLayout.LayoutParams(size, size, Gravity.CENTER))

        // Círculo principal: gradiente escuro-roxo profundo + borda neon suave +
        // sombra sutil (profundidade discreta).
        val circle = FrameLayout(this)
        val circleLp = FrameLayout.LayoutParams(dp(BUBBLE_CIRCLE_DP), dp(BUBBLE_CIRCLE_DP), Gravity.CENTER)
        circleLp.setMargins(dp(6), dp(6), dp(6), dp(6))
        val circleBg = android.graphics.drawable.GradientDrawable()
        circleBg.shape = android.graphics.drawable.GradientDrawable.OVAL
        circleBg.gradientType = android.graphics.drawable.GradientDrawable.RADIAL_GRADIENT
        circleBg.setGradientCenter(0.42f, 0.38f)
        circleBg.setColors(intArrayOf(0xFF4C37B8.toInt(), 0xFF2A1B70.toInt(), 0xFF150B3A.toInt()))
        circleBg.setStroke(dp(1), COLOR_NEON_BORDER)
        circle.background = circleBg
        circle.elevation = dp(4).toFloat()
        root.addView(circle, circleLp)

        // Ícone central (controle de jogo/captura — vetorial, sem texto).
        val icon = ImageView(this)
        icon.setImageResource(R.drawable.ic_game_live_capture)
        icon.scaleType = ImageView.ScaleType.CENTER_INSIDE
        circle.addView(icon, FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER))

        // Indicador discreto de transmissão ativa (ponto vivo, estático).
        val dot = View(this)
        val dotBg = android.graphics.drawable.GradientDrawable()
        dotBg.shape = android.graphics.drawable.GradientDrawable.OVAL
        dotBg.setColor(COLOR_LIVE_DOT)
        dotBg.setStroke(dp(1), 0xFF3A1B36.toInt())
        dot.background = dotBg
        dot.elevation = dp(2).toFloat()
        val dotLp = FrameLayout.LayoutParams(dp(8), dp(8), Gravity.END or Gravity.BOTTOM)
        dotLp.setMargins(0, 0, dp(2), dp(2))
        circle.addView(dot, dotLp)

        root.setOnClickListener {
            // Toggle: painel aberto → fechar (mantém a bolinha); fechado → abrir.
            if (panelView != null) closePanel() else openPanel()
        }
        root.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var dragging = false

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = bubbleCollapsedX
                        initialY = bubbleCollapsedY
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        dragging = false
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        if (!dragging && (dx * dx + dy * dy) > dp(8) * dp(8)) {
                            dragging = true
                        }
                        if (dragging) {
                            var newX = initialX + dx
                            var newY = initialY + dy
                            bubbleCollapsedX = clampX(newX)
                            bubbleCollapsedY = clampY(newY)
                            val params = bubbleLayoutParams()
                            params.x = bubbleCollapsedX
                            params.y = bubbleCollapsedY
                            try { wm.updateViewLayout(v, params) } catch (_: Exception) {}
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (dragging) {
                            // Ajusta a bolinha para a borda horizontal mais
                            // próxima (sem travar em um único canto — pode ficar
                            // em qualquer altura) e mantém dentro dos limites.
                            snapToEdge()
                            val params = bubbleLayoutParams()
                            params.x = bubbleCollapsedX
                            params.y = bubbleCollapsedY
                            try { wm.updateViewLayout(v, params) } catch (_: Exception) {}
                        } else {
                            // Realiza um "tap" se não arrastou
                            v.performClick()
                        }
                        return true
                    }
                }
                return false
            }
        })

        return root
    }

    private fun bubbleLayoutParams(): WindowManager.LayoutParams {
        val density = resources.displayMetrics.density
        val size = bubbleSize()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        return WindowManager.LayoutParams(
            size,
            size,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = bubbleCollapsedX
            y = bubbleCollapsedY
        }
    }

    private fun bubbleSize(): Int = dp(BUBBLE_SIZE_DP)

    private fun clampX(x: Int): Int {
        val size = bubbleSize()
        val margin = safeMargin()
        val minX = safeLeft + margin
        val maxX = (screenWidth - safeRight - size - margin).coerceAtLeast(minX)
        return x.coerceIn(minX, maxX)
    }

    private fun clampY(y: Int): Int {
        val size = bubbleSize()
        val margin = safeMargin()
        val minY = safeTop + margin
        val maxY = (screenHeight - safeBottom - size - margin).coerceAtLeast(minY)
        return y.coerceIn(minY, maxY)
    }

    private fun clampBubbleToBounds() {
        bubbleCollapsedX = clampX(bubbleCollapsedX)
        bubbleCollapsedY = clampY(bubbleCollapsedY)
    }

    /** Ajusta a bolinha para a borda horizontal mais próxima, mantendo a
     *  altura livre (não fica presa em um único canto). */
    private fun snapToEdge() {
        val size = bubbleSize()
        val leftDist = bubbleCollapsedX
        val rightDist = screenWidth - (bubbleCollapsedX + size)
        bubbleCollapsedX = if (leftDist <= rightDist) 0 else (screenWidth - size)
        bubbleCollapsedY = clampY(bubbleCollapsedY)
    }

    // -------------------------------------------------------------------------
    // Indicador de painel ocultado (ocultar NÃO encerra a live)
    // -------------------------------------------------------------------------

    /** Centraliza a transição mostrar/ocultar: atualiza o estado, reposiciona os
     *  views e espelha o estado no Flutter (Native → Dart). */
    private fun setHidden(hide: Boolean) {
        hidden = hide
        if (hide) showHiddenIndicator() else showBubble()
        notifyAction("overlayVisibilityChanged", mapOf("hidden" to hidden))
    }

    private fun showHiddenIndicator() {
        removeBubble()
        removePanel()
        if (hiddenIndicatorView != null) return
        val wm = windowManager ?: return
        val isOverlayGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(this)
        if (!isOverlayGranted) return

        val tab = ImageView(this)
        tab.setImageResource(R.drawable.ic_game_live_capture)
        tab.scaleType = ImageView.ScaleType.CENTER_INSIDE
        val w = dp(44)
        val h = dp(68)
        tab.setPadding(dp(10), dp(18), dp(10), dp(18))
        tab.background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = dp(14).toFloat()
            setColor(0xF02A1B70.toInt())
            setStroke(dp(1), COLOR_NEON_BORDER)
        }
        tab.setOnClickListener { setHidden(false) }

        hiddenIndicatorView = tab
        try {
            wm.addView(tab, hiddenIndicatorLayoutParams())
            Log.i(TAG, "showHiddenIndicator: indicador ADICIONADO ao WindowManager")
        } catch (t: Throwable) {
            Log.e(TAG, "showHiddenIndicator: falha ao adicionar indicador ao WindowManager", t)
            hiddenIndicatorView = null
        }
    }

    private fun hiddenIndicatorLayoutParams(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        val w = dp(44)
        val h = dp(68)
        val margin = dp(6)
        val x = if (bubbleCollapsedX + bubbleSize() < screenWidth / 2)
            safeLeft + margin else (screenWidth - safeRight - w - margin)
        val y = clampY(bubbleCollapsedY + bubbleSize() / 2 - h / 2)
        return WindowManager.LayoutParams(
            w,
            h,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            this.x = x
            this.y = y
        }
    }

    private fun repositionHiddenIndicator() {
        hiddenIndicatorView?.let { v ->
            try {
                windowManager?.updateViewLayout(v, hiddenIndicatorLayoutParams())
            } catch (_: Exception) {}
        }
    }

    private fun removeHiddenIndicator() {
        hiddenIndicatorView?.let { v ->
            try { windowManager?.removeView(v) } catch (_: Exception) {}
        }
        hiddenIndicatorView = null
    }

    // -------------------------------------------------------------------------
    // Painel de controles
    // -------------------------------------------------------------------------

    private fun openPanel() {
        if (panelView != null) return
        val wm = windowManager ?: return
        val panel = createPanelView(wm)
        panelView = panel
        try {
            wm.addView(panel, panelLayoutParams())
            Log.i(TAG, "openPanel: painel ADICIONADO ao WindowManager")
        } catch (t: Throwable) {
            Log.e(TAG, "openPanel: falha ao adicionar painel ao WindowManager", t)
            panelView = null
        }
        refreshControls()
        notifyAction("panelVisibilityChanged", mapOf("open" to true))
    }

    private fun panelLayoutParams(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        // Compacto: acompanha o conteúdo (grade 2×4), nunca ocupa a maior
        // parte da tela — o vídeo/jogo continua visível ao redor.
        return WindowManager.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.CENTER
        }
    }

    private var micButton: TextView? = null
    private var pauseButton: TextView? = null
    private var voiceButton: TextView? = null

    @SuppressLint("SetTextI18n")
    private fun createPanelView(wm: WindowManager): View {
        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(dp(12), dp(14), dp(12), dp(14))
        root.background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = dp(18).toFloat()
            setColor(0xF2100C22.toInt())
            setStroke(dp(1), COLOR_NEON_BORDER)
        }
        root.elevation = dp(12).toFloat()

        // Título compacto
        val title = TextView(this)
        title.text = "🎮 Controles da Live"
        title.setTextColor(0xFFFFFFFF.toInt())
        title.textSize = 13f
        title.setTypeface(null, Typeface.BOLD)
        title.gravity = Gravity.CENTER
        root.addView(title, compactContainer())

        // Grade 2×4 de botões menores (ícones claros + rótulo pequeno).
        micButton = controlChip("🎤", "Mic")
        pauseButton = controlChip("⏸️", "Pausar")
        voiceButton = controlChip("🤖", "Voz")
        val moreButton = controlChip("⚙️", "Mais")
        val homeButton = controlChip("🏠", "Voltar")

        micButton!!.setOnClickListener {
            micEnabled = !micEnabled
            notifyAction("micToggled", mapOf("enabled" to micEnabled))
            refreshControls()
        }
        pauseButton!!.setOnClickListener {
            paused = !paused
            notifyAction("pauseToggled", mapOf("paused" to paused))
            refreshControls()
        }
        voiceButton!!.setOnClickListener {
            voiceBotEnabled = !voiceBotEnabled
            notifyAction("voiceBotToggled", mapOf("enabled" to voiceBotEnabled))
            refreshControls()
        }
        moreButton.setOnClickListener {
            notifyAction("morePressed", null)
        }
        homeButton.setOnClickListener {
            closePanel()
            notifyAction("backToAppRequested", null)
        }

        root.addView(chipRow(micButton!!, pauseButton!!, voiceButton!!, moreButton, homeButton), compactContainer())

        val chatButton = controlChip("💬", "Chat")
        val hideButton = controlChip("🙈", "Ocultar")
        val endButton = controlChip("🔴", "Encerrar")
        val closeButton = controlChip("✕", "Fechar")

        chatButton.setOnClickListener {
            closePanel()
            notifyAction("chatRequested", null)
        }
        hideButton.setOnClickListener { setHidden(true) }
        endButton.setOnClickListener { confirmEnd() }
        closeButton.setOnClickListener { closePanel() }

        root.addView(chipRow(chatButton, hideButton, endButton, closeButton), compactContainer())

        return root
    }

    private fun chipRow(vararg chips: TextView): LinearLayout {
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        row.gravity = Gravity.CENTER
        for (chip in chips) {
            val lp = LinearLayout.LayoutParams(dp(CHIP_WIDTH_DP), dp(CHIP_HEIGHT_DP))
            lp.setMargins(dp(2), 0, dp(2), 0)
            row.addView(chip, lp)
        }
        return row
    }

    private fun controlChip(emoji: String, label: String): TextView {
        val tv = TextView(this)
        tv.text = "$emoji\n$label"
        tv.setTextColor(0xFFFFFFFF.toInt())
        tv.textSize = 11f
        tv.setTypeface(null, Typeface.BOLD)
        tv.gravity = Gravity.CENTER
        tv.setPadding(dp(2), dp(4), dp(2), dp(4))
        tv.setLineSpacing(0f, 0.9f)
        tv.background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = dp(12).toFloat()
            setColor(0xFF1A1630.toInt())
            setStroke(dp(1), 0x338B5CF6.toInt())
        }
        return tv
    }

    private fun refreshControls() {
        micButton?.let { if (it.isAttachedToWindow) updateChip(it, "🎤", "Mic", micEnabled) }
        pauseButton?.let { if (it.isAttachedToWindow) updateChip(it, if (paused) "▶️" else "⏸️", if (paused) "Retomar" else "Pausar", !paused) }
        voiceButton?.let { if (it.isAttachedToWindow) updateChip(it, "🤖", "Voz", voiceBotEnabled) }
        if (panelView != null) showForegroundNotification()
    }

    private fun updateChip(tv: TextView, emoji: String, label: String, active: Boolean) {
        tv.text = "$emoji\n$label"
        (tv.background as? android.graphics.drawable.GradientDrawable)?.apply {
            if (active) {
                setColor(0xFF6D28D9.toInt())
                setStroke(dp(1), COLOR_NEON_BORDER)
            } else {
                setColor(0xFF1A1630.toInt())
                setStroke(dp(1), 0x338B5CF6.toInt())
            }
        }
    }

    private fun closePanel() {
        Log.d(TAG, "closePanel: ocultando painel (bolinha permanece)")
        removePanel()
        notifyAction("panelVisibilityChanged", mapOf("open" to false))
    }

    private fun confirmEnd() {
        // A confirmação final acontece no app (Flutter), que exibe um dialog.
        closePanel()
        notifyAction("endRequested", null)
    }

    private fun removeBubble() {
        bubbleView?.let { v ->
            try { windowManager?.removeView(v) } catch (_: Exception) {}
        }
        bubbleView = null
    }

    private fun removePanel() {
        panelView?.let { v ->
            try { windowManager?.removeView(v) } catch (_: Exception) {}
        }
        panelView = null
    }

    private fun removeViews() {
        removeBubble()
        removePanel()
        removeHiddenIndicator()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy: removendo views e encerrando service de overlay")
        removeViews()
        // Espelho Native → Dart: a bolinha saiu. O Dart decide o que fazer com
        // a live (que continua no ar) — por isso SEMPRE avisamos aqui, inclusive
        // quando o Android/usuário encerrou o service sem passar pelo app.
        notifyAction("overlayStopped", null)
        instance = null
        // Garante que o canal não fique preso em referências de uma instância
        // morta (o onDestroy corre ANTES de qualquer start subsequente).
        if (channel == null || pendingChannel === channel) pendingChannel = null
        super.onDestroy()
    }

    // -------------------------------------------------------------------------
    // Helpers de layout / dimensão
    // -------------------------------------------------------------------------

    private fun compactContainer(): LinearLayout.LayoutParams {
        val lp = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        lp.setMargins(0, dp(6), 0, 0)
        return lp
    }

    private fun dp(value: Int): Int {
        val density = resources.displayMetrics.density
        return (value * density).toInt()
    }
}
