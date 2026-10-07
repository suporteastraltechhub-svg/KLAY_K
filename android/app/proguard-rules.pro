# Regras de R8/ProGuard do KLAY K.
#
# Este arquivo estava referenciado pela configuracao de release mas nao
# existia, o que fazia o AGP emitir:
#   "Supplied proguard configuration does not exist: .../proguard-rules.pro"
#
# A minificacao esta DESLIGADA no release (isMinifyEnabled = false) porque o
# R8 estourava a memoria da maquina de build. As regras abaixo ficam prontas
# para o caso de a minificacao ser reativada depois: sem elas, LiveKit,
# Supabase/PostgREST e Firebase usam reflexao e seriam quebrados em runtime.

# Flutter / AndroidX
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Supabase (gotrue / postgrest) e Postgres
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# Firebase (FCM como transporte)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# LiveKit
-keep class io.livekit.** { *; }
-dontwarn io.livekit.**

# org.webrtc / flutter_webrtc
-keep class org.webrtc.** { *; }
-keep class com.infobip.** { *; }
-dontwarn org.webrtc.**

# Play Core / split install
-dontwarn com.google.android.play.core.**
