import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:csv/csv.dart';

// ==============================
// Classification Testing Screen
// ==============================
class ClassificationTesting extends StatefulWidget {
  @override
  _ClassificationTestingState createState() => _ClassificationTestingState();
}

class _ClassificationTestingState extends State<ClassificationTesting> {
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  StreamSubscription<List<int>>? _characteristicSubscription;

  String statusText = "Initializing...";
  bool _permissionsGranted = false;
  bool _permissionsChecked = false;

  static const String arduinoMacAddress = "D4:AB:D0:31:C3:3F";

  static const List<String> exercises = [
    "Squat",
    "RomanianDeadlift",
    "BarbellRows",
    "BicepCurl",
    "NoExercice",
    "Unknown",
  ];

  final Map<String, int> classificationCounts = {
    "Squat": 0,
    "RomanianDeadlift": 0,
    "BarbellRows": 0,
    "BicepCurl": 0,
    "NoExercice": 0,
    "Unknown": 0,
  };

  // ==============================
  // Lifecycle
  // ==============================
  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _characteristicSubscription?.cancel();
    targetDevice?.disconnect();
    super.dispose();
  }

  Future<void> _init() async {
    await _checkAndRequestPermissions();

    if (!_permissionsGranted) {
      if (mounted) {
        setState(() {
          statusText = "Bluetooth & Location permissions required";
        });
      }
      return;
    }

    startScanning();
  }

  // ==============================
  // Permissions (SAFE for Android 14)
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
  // Bluetooth Scan
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
          debugPrint(
              "Found: ${r.device.id} | ${r.device.name} | RSSI: ${r.rssi}");

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
      if (mounted) {
        setState(() => statusText = "Scan failed: $e");
      }
    }
  }

  // ==============================
  // Device Connection
  // ==============================
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      setState(() => statusText = "Connecting to Arduino...");
      await device.connect(timeout: const Duration(seconds: 30));

      targetDevice = device;
      setState(() => statusText = "Connected");

      final services = await device.discoverServices();

      for (final service in services) {
        if (service.uuid.toString() ==
            "19b10000-e8f2-537e-4f6c-d104768a1214") {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid.toString() ==
                "19b10001-e8f2-537e-4f6c-d104768a1214") {
              targetCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);

              _characteristicSubscription =
                  characteristic.value.listen((value) {
                final data = String.fromCharCodes(value);
                processData(data);
              });
            }

            if (characteristic.uuid.toString() ==
                "19b10002-e8f2-537e-4f6c-d104768a1214") {
              await characteristic.write(
                "WORKOUT_TRACKER".codeUnits,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Connection error: $e");
      if (mounted) {
        setState(() => statusText = "Connection failed");
      }
    }
  }

  // ==============================
  // Data Processing
  // ==============================
  void processData(String data) {
    if (data.isEmpty) return;

    final values = data.split(",");

    if (values.length == 4 && values[3].startsWith("exercise:")) {
      String exercise = values[3].split(":")[1].trim();

      if (exercise.endsWith("Deadli")) {
        exercise = "RomanianDeadlift";
      }

      setState(() {
        statusText = "Detected: $exercise";
        classificationCounts[exercise] =
            (classificationCounts[exercise] ?? 0) + 1;
      });
    } else {
      debugPrint("Unexpected data: $data");
    }
  }

  // ==============================
  // UI
  // ==============================
  @override
  Widget build(BuildContext context) {
    if (!_permissionsGranted) {
      return Scaffold(
        appBar: AppBar(title: const Text("Classification Testing")),
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
      appBar: AppBar(title: const Text("Classification Testing")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("Status: $statusText"),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final exercise = exercises[index];
                return ListTile(
                  title: Text(exercise),
                  trailing: Text(
                    "Count: ${classificationCounts[exercise]}",
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: targetDevice != null
                  ? () => targetDevice!.disconnect()
                  : null,
              child: const Text("Disconnect"),
            ),
          ),
        ],
      ),
    );
  }
}
