class AppConfig {
  // ── Supabase ──────────────────────────────────────────────
  static const String supabaseUrl = 'https://stxqefcjhrrriazoqjev.supabase.co';
  static const String supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN0eHFlZmNqaHJycmlhem9xamV2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3Mjk1MjQsImV4cCI6MjA5NTMwNTUyNH0.ePsxYpI-oKraEIGuZl4P0uEu2kp6ET6x42_Z-d_DEMA';       // paste from Step 4
  

  // RSSI threshold for proximity
  // -60 = very close (1-2m)
  // -70 = medium (3-5m)  ← start here
  // -80 = far (roughly classroom sized)
  // Calibrate on-site because walls and phone models vary.
  static const int rssiThreshold      = -100;
  static const int scanRestartSeconds = 8;

  /// Lenient RSSI for exam join only (continuous monitoring may stay stricter).
  static const int examJoinRssiThreshold = -95;

  /// Max time to scan for teacher beacon when joining an exam.
  static const int examJoinScanTimeoutSeconds = 8;

  /// Join exam: in-range ticks on the same continuous scan as attendance (see [BleService]).
  static const int examJoinInRangeStreakRequired = 1;

  /// Keep student IN RANGE briefly after a missed exam beacon scan.
  static const int examProximitySmoothingSeconds = 5;

  /// Show BLE debug panel on student exam screens (set false for production).
  static const bool showExamBleDebugPanel = true;

  // BLE service UUID used as teacher beacon identifier.
  static const String defaultBeaconUuid =
      '12345678-1234-1234-1234-123456789012';
  static const String defaultBeaconName = 'PROFATTN';
}