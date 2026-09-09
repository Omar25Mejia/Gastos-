// Configuración pública del cliente. El anon key de Supabase está diseñado para uso público,
// pero las tablas deben estar protegidas con RLS. NUNCA pongás aquí service_role keys.
window.SUPABASE_CONFIG={
  url:'YOUR_SUPABASE_URL',
  anonKey:'YOUR_SUPABASE_ANON_KEY'
};