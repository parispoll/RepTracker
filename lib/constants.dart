class AppConstants {
  // ==============================
  // Bluetooth
  // ==============================
  /// Arduino BLE MAC address (uppercase, colon-separated)
  static const String arduinoMacAddress = "D4:AB:D0:31:C3:3F";

  // ==============================
  // Exercise Labels (STANDARDIZED)
  // ==============================
  /// These strings MUST match:
  /// - Arduino firmware output
  /// - Flutter classification logic
  /// - Session export & stats
  static const List<String> exercises = [
    "Squat",
    "RomanianDeadlift",
    "BarbellRows",
    "BicepCurl",
    "None",
    "Unknown",
  ];

  // ==============================
  // Rep / Set Detection
  // ==============================
  /// Time without reps to consider a set finished (ms)
  static const int setRestThreshold = 5000;

  /// Minimum time between detected reps (ms)
  static const int minRepInterval = 1500;

  /// Transition debounce time (Idle <-> Exercise) (ms)
  static const int transitionDelay = 1000;

  /// Baseline Z-axis gravity offset (m/s²)
  static const double zBaseline = -9.65;

  // ==============================
  // Smoothing & Idle Detection
  // ==============================
  /// Moving average window size (samples)
  static const int smoothingWindowSize = 5;

  /// Window used to detect idle state (samples)
  static const int idleWindowSize = 100;

  /// Max Z variation considered idle (m/s²)
  static const double idleZThreshold = 0.1;

  // ==============================
  // Peak Detection
  // ==============================
  /// Z-axis peak threshold for rep detection (m/s²)
  static const double zThreshold = 0.5;
}
