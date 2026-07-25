/// Configuración de Supabase
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ntanwjuivejwxrpnmesk.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im50YW53anVpdmVqd3hycG5tZXNrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ3NTkwMDksImV4cCI6MjEwMDMzNTAwOX0.j2p0srLRMzWnvs6r9p4PMFqtgoNn9BmXGYS7Y29u8Xc',
  );
}
