import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'constants.dart';

// ==============================
// Workout Tracker
// ==============================
class WorkoutTracker extends StatefulWidget {
  @override
  _WorkoutTrackerState createState() => _WorkoutTrackerState();
}

class _WorkoutTrackerState extends State<WorkoutTracker> {
  // Bluetooth
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  StreamSubscription<List<int>>? _characteristicSubscription;

  static const String arduinoMacAddress = "D4:AB:D0:31:C3:3F";

  // Permissions
  bool _permissionsGranted = false;
  bool _permissionsChecked = false;

  // Status
  String statusText = "Initializing...";

  // Exercises
  static const List<String> exercises = [
    "Squat",
    "Deadlift",
    "BarbellRows",
    "BicepCurl",
    "NoExercice",
    "unknown",
  ];

  Map<String, Map<String, int>> exerciseStats = {
    for (var e in exercises) e: {"reps": 0, "sets": 0},
  };

  String currentExercise = "unknown";
  int currentReps = 0;
  int currentSets = 0;

  // Rep detection
  DateTime? lastRepTime;
  DateTime? lastRepDetectionTime;
  DateTime? lastIdleTime;
  DateTime? lastSetTime;

  bool isIdle = true;

  static const int setRestThreshold = 5000;
  static const int minRepInterval = 1500;
  static const int transitionDelay = 1000;
  static const double zBaseline = -9.65;

  // Smoothing / idle
  List<double> zWindow = [];
  static const int smoothingWindowSize = 5;

  List<double> idleWindow = [];
  static const int idleWindowSize = 100;
  static const double idleZThreshold = 0.1;

  double? lastZ;
  double? lastSmoothedZ;
  bool isMovingUp = false;
  bool isMovingDown = false;
  static const double zThreshold = 0.5;

  // Session logging
  List<List<dynamic>> sessionData = [];
  int setStartIndex = 1;
  Map<String, int> exerciseCounts = {};

  // ==============================
  // Lifecycle
  // ==============================
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    sessionData.add([
      "Timestamp",
      "Raw Z",
      "Normalized Z",
      "Smoothed Z",
      "Rep Detected",
      "isIdle",
      "Current Reps",
      "Current Sets",
      "Exercise",
    ]);

    for (final e in exercises) {
      exerciseCounts[e] = 0;
    }

    _init();
  }

  @override
  void dispose() {
    _characteristicSubscription?.cancel();
    targetDevice?.disconnect();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _init() async {
    await _checkAndRequestPermissions();

    if (!_permissionsGranted) {
      setState(() {
        statusText = "Bluetooth & Location permissions required";
      });
      return;
    }

    startScanning();
  }

  // ==============================
  // Permissions (Android 13/14 SAFE)
  // ==============================
  Future<void> _checkAndRequestPermissions() async {
    if (_permissionsChecked) return;
    _permissionsChecked = true;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    _permissionsGranted =
        statuses.values.every((status) => status.isGranted);

    debugPrint("Permission status: $statuses");
  }

  // ==============================
  // Bluetooth
  // ==============================
  Future<void> startScanning() async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        setState(() => statusText = "Bluetooth not supported");
        return;
      }

      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        setState(() => statusText = "Please turn ON Bluetooth");
        return;
      }

      setState(() => statusText = "Scanning for Arduino...");
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (r.device.id.toString().toUpperCase() ==
              arduinoMacAddress.toUpperCase()) {
            FlutterBluePlus.stopScan();
            connectToDevice(r.device);
            break;
          }
        }
      });
    } catch (e) {
      debugPrint("Scan error: $e");
      setState(() => statusText = "Scan failed");
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      setState(() => statusText = "Connecting...");
      await device.connect(timeout: const Duration(seconds: 30));

      targetDevice = device;
      setState(() => statusText = "Connected");

      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.toString() ==
            "19b10000-e8f2-537e-4f6c-d104768a1214") {
          for (final c in service.characteristics) {
            if (c.uuid.toString() ==
                "19b10001-e8f2-537e-4f6c-d104768a1214") {
              await c.setNotifyValue(true);
              _characteristicSubscription =
                  c.value.listen((v) {
                processData(String.fromCharCodes(v));
              });
            }

            if (c.uuid.toString() ==
                "19b10002-e8f2-537e-4f6c-d104768a1214") {
              await c.write("WORKOUT_TRACKER".codeUnits);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Connection failed: $e");
      setState(() => statusText = "Connection failed");
    }
  }

  // ==============================
  // Data Processing
  // ==============================
  void processData(String data) {
    if (data.isEmpty) return;

    final values = data.split(",");
    if (values.length < 3) return;

    final z = double.tryParse(values[2]) ?? 0;
    final exercise =
        values.length == 4 && values[3].startsWith("exercise:")
            ? values[3].split(":")[1].trim()
            : "unknown";

    detectRep(z, DateTime.now(), exercise);

    setState(() {
      currentExercise = exercise;
      statusText =
          "Exercise: $currentExercise | Reps: $currentReps | Sets: $currentSets";
    });
  }

  // ==============================
  // Rep Detection (UNCHANGED LOGIC)
  // ==============================
  void detectRep(double z, DateTime now, String classifiedExercise) {
    exerciseCounts[classifiedExercise] =
        (exerciseCounts[classifiedExercise] ?? 0) + 1;

    final normalizedZ = z - zBaseline;

    idleWindow.add(normalizedZ);
    if (idleWindow.length > idleWindowSize) idleWindow.removeAt(0);

    if (idleWindow.length == idleWindowSize) {
      final minZ = idleWindow.reduce(min);
      final maxZ = idleWindow.reduce(max);
      isIdle = (maxZ - minZ) < idleZThreshold;
      if (isIdle) lastIdleTime = now;
    }

    zWindow.add(normalizedZ);
    if (zWindow.length > smoothingWindowSize) zWindow.removeAt(0);
    final smoothedZ =
        zWindow.reduce((a, b) => a + b) / zWindow.length;

    if (lastRepDetectionTime != null &&
        now.difference(lastRepDetectionTime!).inMilliseconds <
            minRepInterval) {
      _logData(now, z, normalizedZ, smoothedZ, false);
      lastZ = z;
      lastSmoothedZ = smoothedZ;
      return;
    }

    if (_inTransition(now)) {
      _logData(now, z, normalizedZ, smoothedZ, false);
      lastZ = z;
      lastSmoothedZ = smoothedZ;
      return;
    }

    bool repDetected = false;

    if (lastSmoothedZ != null) {
      final delta = smoothedZ - lastSmoothedZ!;
      final movingUpNow = delta > 0;
      if (isMovingUp && !movingUpNow && smoothedZ > zThreshold) {
        currentReps++;
        lastRepTime = now;
        lastRepDetectionTime = now;
        repDetected = true;
      }
      isMovingUp = movingUpNow;
    }

    _logData(now, z, normalizedZ, smoothedZ, repDetected);

    if (lastRepTime != null &&
        now.difference(lastRepTime!).inMilliseconds >
            setRestThreshold &&
        currentReps > 0) {
      _completeSet(now);
    }

    lastZ = z;
    lastSmoothedZ = smoothedZ;
  }

  bool _inTransition(DateTime now) {
    if (lastIdleTime != null &&
        !isIdle &&
        now.difference(lastIdleTime!).inMilliseconds <
            transitionDelay) return true;

    if (lastSetTime != null &&
        now.difference(lastSetTime!).inMilliseconds <
            transitionDelay) return true;

    return false;
  }

  void _logData(DateTime t, double z, double nz, double sz, bool rep) {
    sessionData.add([
      t.toIso8601String(),
      z,
      nz,
      sz,
      rep ? 1 : 0,
      isIdle ? 1 : 0,
      currentReps,
      currentSets,
      "",
    ]);
  }

  void _completeSet(DateTime now) {
    final setExercise = classifySet();

    for (int i = setStartIndex; i < sessionData.length; i++) {
      sessionData[i][8] = setExercise;
    }

    exerciseStats[setExercise]!["reps"] =
        (exerciseStats[setExercise]!["reps"] ?? 0) + currentReps;
    exerciseStats[setExercise]!["sets"] =
        (exerciseStats[setExercise]!["sets"] ?? 0) + 1;

    currentSets++;
    currentReps = 0;
    lastRepTime = null;
    lastSetTime = now;

    setStartIndex = sessionData.length;
    exerciseCounts.updateAll((k, v) => 0);
  }

  String classifySet() {
    String best = "unknown";
    int maxCount = 0;

    exerciseCounts.forEach((k, v) {
      if (v > maxCount && k != "NoExercice" && k != "unknown") {
        best = k;
        maxCount = v;
      }
    });

    return best;
  }

  // ==============================
  // Save Session
  // ==============================
  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('saved_sessions');

    final Map<String, dynamic> sessions =
        existing != null ? jsonDecode(existing) : {};

    final name = "session_${DateTime.now().millisecondsSinceEpoch}";
    sessions[name] = sessionData;

    await prefs.setString('saved_sessions', jsonEncode(sessions));

    setState(() {
      statusText = "Session saved";
    });
  }

  // ==============================
  // UI
  // ==============================
  @override
  Widget build(BuildContext context) {
    if (!_permissionsGranted) {
      return Scaffold(
        appBar: AppBar(title: const Text("Workout Tracker")),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Bluetooth & Location permissions are required.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: openAppSettings,
                child: const Text("Open App Settings"),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Workout Tracker")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("Status: $statusText"),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: AppConstants.exercises.length,
              itemBuilder: (context, i) {
                final e = AppConstants.exercises[i];
                return ListTile(
                  title: Text(e),
                  subtitle: Text(
                    "Sets: ${exerciseStats[e]?['sets']} | "
                    "Reps: ${exerciseStats[e]?['reps']}",
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed:
                    targetDevice != null ? targetDevice!.disconnect : null,
                child: const Text("Disconnect"),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed:
                    targetDevice == null ? startScanning : null,
                child: const Text("Reconnect"),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _saveSession,
                child: const Text("Save Session"),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
