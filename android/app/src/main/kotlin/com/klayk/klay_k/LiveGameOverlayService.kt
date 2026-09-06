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
import android.widget.ImageButton
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
    private var minimizedView: View? = null

    private var bubbleCollapsedX = 24
    private var bubbleCollapsedY = 320

    // Dimensões atuais da tela (recalculadas em onConfigurationChanged).
    private var screenWidth = 0
    private var screenHeight = 0

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
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Mantém a posição da bolinha dentro da nova área após rotação.
        updateScreenSize()
        clampBubbleToBounds()
        bubbleView?.let { v ->
            val params = bubbleLayoutParams()
            params.x = bubbleCollapsedX
            params.y = bubbleCollapsedY
            try { windowManager?.updateViewLayout(v, params) } catch (_: Exception) {}
        }
        repositionMinimized()
    }

    private fun updateScreenSize() {
        val metrics = resources.displayMetrics
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handleIntent(intent)
        return START_STICKY
    }

    private fun handleIntent(intent: Intent?) {
        when (intent?.action) {
            ACTION_START, null -> {
                showForegroundNotification()
                if (hidden) showMinimized() else showBubble()
            }
            ACTION_HIDE -> hideBubble()
            ACTION_RESTORE -> { hidden = false; showBubble() }
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
            "hide" -> hideBubble()
            "restore" -> { hidden = false; showBubble() }
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

            startForeground(NOTIFICATION_ID, notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
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
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createBubbleView(wm: WindowManager): View {
        val size = dp(58)
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.HORIZONTAL
        layout.gravity = Gravity.CENTER
        layout.setBackgroundResource(android.R.color.transparent)

        val badge = TextView(this)
        badge.text = "🎮"
        badge.textSize = 24f
        val lp = LinearLayout.LayoutParams(size, size)
        layout.addView(badge, lp)

        layout.setOnClickListener {
            // Toggle: painel aberto → fechar (mantém a bolinha); fechado → abrir.
            if (panelView != null) closePanel() else openPanel()
        }
        layout.setOnTouchListener(object : View.OnTouchListener {
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

        // Círculo arredondado
        layout.background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.OVAL
            setColor(0xF0281B70.toInt())
            setStroke(dp(2), 0xFF8B5CF6.toInt())
        }

        return layout
    }

    private fun bubbleLayoutParams(): WindowManager.LayoutParams {
        val density = resources.displayMetrics.density
        val size = (58 * density).toInt()
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

    private fun bubbleSize(): Int {
        val density = resources.displayMetrics.density
        return (58 * density).toInt()
    }

    private fun clampX(x: Int): Int {
        val size = bubbleSize()
        val minX = 0
        val maxX = (screenWidth - size).coerceAtLeast(0)
        return x.coerceIn(minX, maxX)
    }

    private fun clampY(y: Int): Int {
        val size = bubbleSize()
        val minY = 0
        val maxY = (screenHeight - size).coerceAtLeast(0)
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
    // Indicador minimizado (ocultar NÃO encerra a live)
    // -------------------------------------------------------------------------

    private fun showMinimized() {
        removeBubble()
        removePanel()
        if (minimizedView != null) return
        val wm = windowManager ?: return
        val isOverlayGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(this)
        if (!isOverlayGranted) return

        val tab = TextView(this)
        tab.text = "🎮"
        tab.textSize = 20f
        tab.gravity = Gravity.CENTER
        tab.setTextColor(0xFFFFFFFF.toInt())
        val w = dp(40)
        val h = dp(64)
        tab.background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = dp(12).toFloat()
            setColor(0xE0281B70.toInt())
            setStroke(dp(2), 0xFF8B5CF6.toInt())
        }
        tab.setOnClickListener { restoreBubble() }

        minimizedView = tab
        try {
            wm.addView(tab, minimizedLayoutParams())
            Log.i(TAG, "showMinimized: indicador minimizado ADICIONADO ao WindowManager")
        } catch (t: Throwable) {
            Log.e(TAG, "showMinimized: falha ao adicionar indicador ao WindowManager", t)
            minimizedView = null
        }
    }

    private fun minimizedLayoutParams(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        val w = dp(40)
        val h = dp(64)
        val margin = dp(6)
        val x = if (bubbleCollapsedX + bubbleSize() < screenWidth / 2)
            margin else (screenWidth - w - margin)
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

    private fun repositionMinimized() {
        minimizedView?.let { v ->
            try {
                windowManager?.updateViewLayout(v, minimizedLayoutParams())
            } catch (_: Exception) {}
        }
    }

    private fun restoreBubble() {
        removeMinimized()
        hidden = false
        showBubble()
    }

    private fun removeMinimized() {
        minimizedView?.let { v ->
            try { windowManager?.removeView(v) } catch (_: Exception) {}
        }
        minimizedView = null
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
    }

    private fun panelLayoutParams(): WindowManager.LayoutParams {
        val width = (resources.displayMetrics.widthPixels * 0.88f).toInt()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        return WindowManager.LayoutParams(
            width,
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
        root.setPadding(dp(20), dp(20), dp(20), dp(20))
        root.setBackgroundResource(android.R.color.transparent)

        // Fundo do painel arredondado
        root.background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = dp(20).toFloat()
            setColor(0xF0181429.toInt())
            setStroke(dp(1), 0xFF8B5CF6.toInt())
        }

        // Título
        val title = TextView(this)
        title.text = "🎮 Painel da Live de Jogo"
        title.setTextColor(0xFFFFFFFF.toInt())
        title.textSize = 16f
        title.setTypeface(null, Typeface.BOLD)
        title.gravity = Gravity.START
        root.addView(title, matchWrap())

        // Linha de botões (mic, pausar, voz, mais)
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        row.gravity = Gravity.CENTER

        micButton = controlChip("🎤", "Mic")
        pauseButton = controlChip("⏸️", "Pausar")
        voiceButton = controlChip("🤖", "Voz")
        val moreButton = controlChip("⚙️", "Mais")

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

        row.addView(micButton, weightWrap())
        row.addView(pauseButton, weightWrap())
        row.addView(voiceButton, weightWrap())
        row.addView(moreButton, weightWrap())
        root.addView(row, matchWrap())

        // Linha de ações secundárias (ocultar, encerrar)
        val row2 = LinearLayout(this)
        row2.orientation = LinearLayout.HORIZONTAL
        row2.gravity = Gravity.CENTER

        val chatButton = controlChip("💬", "Chat", small = true)
        val hideButton = controlChip("🙈", "Ocultar", small = true)
        val endButton = controlChip("🔴", "Encerrar", small = true)
        val closeButton = controlChip("✕", "Fechar", small = true)

        chatButton.setOnClickListener {
            closePanel()
            notifyAction("chatRequested", null)
        }
        hideButton.setOnClickListener { hideBubble() }
        endButton.setOnClickListener { confirmEnd() }
        closeButton.setOnClickListener { closePanel() }

        row2.addView(chatButton, weightWrap())
        row2.addView(hideButton, weightWrap())
        row2.addView(endButton, weightWrap())
        row2.addView(closeButton, weightWrap())
        root.addView(row2, matchWrap())

        // Dica de arrasto
        val hint = TextView(this)
        hint.text = "Arraste a bolinha 🎮 para movê-la pela tela. Você ainda pode usar o app."
        hint.setTextColor(0xAAFFFFFF.toInt())
        hint.textSize = 12f
        root.addView(hint, matchWrap())

        return root
    }

    private fun controlChip(emoji: String, label: String, small: Boolean = false): TextView {
        val tv = TextView(this)
        tv.text = if (small) "$emoji $label" else "  $emoji $label  "
        tv.setTextColor(0xFFFFFFFF.toInt())
        tv.textSize = if (small) 12f else 14f
        tv.setTypeface(null, Typeface.BOLD)
        tv.gravity = Gravity.CENTER
        tv.setPadding(dp(8), dp(10), dp(8), dp(10))
        tv.background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = dp(14).toFloat()
            setColor(0xFF2A2A45.toInt())
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
        tv.text = "$emoji $label"
        (tv.background as? android.graphics.drawable.GradientDrawable)?.setColor(
            if (active) 0xFF8B5CF6.toInt() else 0xFF2A2A45.toInt()
        )
    }

    private fun closePanel() {
        Log.d(TAG, "closePanel: ocultando painel (bolinha permanece)")
        removePanel()
    }

    private fun confirmEnd() {
        // A confirmação final acontece no app (Flutter), que exibe um dialog.
        closePanel()
        notifyAction("endRequested", null)
    }

    private fun hideBubble() {
        hidden = true
        // Ocultar NÃO encerra a live: mantém a transmissão e mostra um
        // indicador discreto na borda para o usuário voltar aos controles.
        showMinimized()
        // A notificação permanece — outra forma de restaurar os controles.
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
        removeMinimized()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy: removendo views e encerrando service de overlay")
        removeViews()
        instance = null
        if (pendingChannel === channel) pendingChannel = null
        super.onDestroy()
    }

    // -------------------------------------------------------------------------
    // Helpers de layout / dimensão
    // -------------------------------------------------------------------------

    private fun matchWrap(): LinearLayout.LayoutParams {
        val lp = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        lp.setMargins(0, dp(8), 0, dp(8))
        return lp
    }

    private fun weightWrap(): LinearLayout.LayoutParams {
        val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        lp.setMargins(dp(4), 0, dp(4), 0)
        return lp
    }

    private fun dp(value: Int): Int {
        val density = resources.displayMetrics.density
        return (value * density).toInt()
    }
}
