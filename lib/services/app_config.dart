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
}