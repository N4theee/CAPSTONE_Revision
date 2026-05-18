class AppConfig {
  // ── Supabase ──────────────────────────────────────────────
  static const String supabaseUrl = 'https://kllzpucxqzhewzoqydmi.supabase.co';
  static const String supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtsbHpwdWN4cXpoZXd6b3F5ZG1pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxMjA4MTIsImV4cCI6MjA5NDY5NjgxMn0.GpnsZizFMR0nepzXJ3E1POIZT_RhAymb_fAq46Y9nic';       // paste from Step 4
  

  // RSSI threshold for proximity
  // -60 = very close (1-2m)
  // -70 = medium (3-5m)  ← start here
  // -80 = far (roughly classroom sized)
  // Calibrate on-site because walls and phone models vary.
  static const int rssiThreshold      = -100;
  static const int scanRestartSeconds = 8;

  // BLE service UUID used as teacher beacon identifier.
  static const String defaultBeaconUuid =
      '12345678-1234-1234-1234-123456789012';
  static const String defaultBeaconName = 'PROFATTN';
}