/// Configuração de integração do KLAY K com Supabase + LiveKit.
///
/// As credenciais abaixo são PÚBLICAS (URL do projeto + publishable key no
/// formato `sb_publishable_...`) e podem ser distribuídas no aplicativo.
/// NADA sensível é gravado neste arquivo: o LiveKit NUNCA é configurado no
/// app — o endereço do servidor e o token de acesso são entregues pela Edge
/// Function `livekit-token`, que lê as credenciais apenas através de Secrets
/// do Supabase (LIVEKIT_URL/LIVEKIT_API_KEY/LIVEKIT_API_SECRET).
///
/// Para apontar para outro projeto sem recompilar, basta informar
/// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...`.
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://oysyuialaelzcxxkfdsl.supabase.co',
  );

  /// Chave pública do projeto (formato `sb_publishable_...`). Pode ser
  /// sobrescrita via `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`.
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_5VdXX67niHP6___GhExvyg_IejTEc4E',
  );

  /// Nome legado (deprecado pelo Supabase) mantido apenas como fallback.
  static const String _legacyAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static const String projectRef = String.fromEnvironment(
    'SUPABASE_PROJECT_REF',
    defaultValue: 'oysyuialaelzcxxkfdsl',
  );

  /// Chave efetiva enviada ao cliente Supabase.
  static String get supabaseKey => supabasePublishableKey.isNotEmpty
      ? supabasePublishableKey
      : _legacyAnonKey;

  /// Quando o Supabase está configurado (por padrão está, com as credenciais
  /// públicas reais), o app usa o backend real; apenas em caso de falha de
  /// rede/backend ele recai no modo demonstração em memória.
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Firebase Cloud Messaging (transporte Android) — opções PÚBLICAS de
  // inicialização do app no Firebase Console:
  //   projectId = astral-tech-hub-f9fb4
  //   appId     = 1:557073766082:android:e4edbec15364f7cc2b4d5b
  //                (cliente com package_name EXATO com.klayk.klay_k)
  //   apiKey    = chave pública do app Android (API key restrita ao pacote)
  //   senderId  = 557073766082 (número do projeto)
  //
  // Estes valores NÃO são segredos (o APK os expõe por natureza): a segurança
  // do envio está inteiramente na Edge Function `send-push` (secrets do
  // Supabase — FCM_SERVICE_ACCOUNT, nunca no app). Podem ser sobrescritos via
  // `--dart-define` (padrão do projeto) caso o app precise apontar para outro
  // projeto Firebase. Nenhuma service account / chave administrativa habita o
  // cliente.
  // ---------------------------------------------------------------------------
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'astral-tech-hub-f9fb4',
  );
  static const String firebaseAppId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:557073766082:android:e4edbec15364f7cc2b4d5b',
  );
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyDHfWXz_zKwLr2TJJWDaWNt4HtVPmnlMUw',
  );
  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '557073766082',
  );

  /// True quando o Firebase (FCM) tem os 4 identificadores públicos
  /// configurados — condição para inicializar e registrar o token de push.
  static bool get isFirebaseConfigured =>
      firebaseProjectId.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseApiKey.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty;
}
