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

class DataAcquisition extends StatefulWidget {
  @override
  _DataAcquisitionState createState() => _DataAcquisitionState();
}

class _DataAcquisitionState extends State<DataAcquisition> {
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  StreamSubscription<List<int>>? _characteristicSubscription;

  String statusText = "Initializing...";
  bool _permissionsGranted = false;
  bool _permissionsChecked = false;

  static const String arduinoMacAddress = "D4:AB:D0:31:C3:3F";

  // Accelerometer data
  List<double> xData = [];
  List<double> yData = [];
  List<double> zData = [];
  final int maxPoints = 100;

  List<Map<String, dynamic>> allAccelData = [];

  int currentReps = 0;
  int currentSets = 0;
  double lastMagnitude = 0;
  bool isRepInProgress = false;
  DateTime? lastRepTime;

  static const double repThreshold = 1.0;
  static const int setRestThreshold = 5000;

  int sampleCount = 0;
  DateTime? lastSampleTime;
  String samplingRateText = "Sampling Rate: N/A";

  final TextEditingController _filenameController = TextEditingController();

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
    _filenameController.dispose();
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
  // Bluetooth Scanning
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
          debugPrint("Found ${r.device.id} | RSSI ${r.rssi}");

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
      if (mounted) setState(() => statusText = "Scan failed");
    }
  }

  // ==============================
  // Device Connection
  // ==============================
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
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid.toString() ==
                "19b10001-e8f2-537e-4f6c-d104768a1214") {
              targetCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);

              _characteristicSubscription =
                  characteristic.value.listen((value) {
                processData(String.fromCharCodes(value));
              });
            }

            if (characteristic.uuid.toString() ==
                "19b10002-e8f2-537e-4f6c-d104768a1214") {
              await characteristic.write(
                "DATA_ACQUISITION".codeUnits,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Connection failed: $e");
      if (mounted) setState(() => statusText = "Connection failed");
    }
  }

  // ==============================
  // Data Processing
  // ==============================
  void processData(String data) {
    if (data.isEmpty) return;

    final values = data.split(",");
    if (values.length < 3) return;

    final x = double.tryParse(values[0]) ?? 0;
    final y = double.tryParse(values[1]) ?? 0;
    final z = double.tryParse(values[2]) ?? 0;

    final timestamp = DateTime.now();
    final magnitude = sqrt(x * x + y * y + z * z);

    _updateSamplingRate(timestamp);
    detectRep(magnitude, timestamp);

    setState(() {
      statusText = "Magnitude: ${magnitude.toStringAsFixed(2)}";

      xData.add(x);
      yData.add(y);
      zData.add(z);

      allAccelData.add({
        'timestamp': timestamp,
        'x': x,
        'y': y,
        'z': z,
      });

      if (xData.length > maxPoints) {
        xData.removeAt(0);
        yData.removeAt(0);
        zData.removeAt(0);
      }
    });
  }

  void _updateSamplingRate(DateTime timestamp) {
    sampleCount++;

    if (lastSampleTime != null && sampleCount % 500 == 0) {
      final elapsedMs =
          timestamp.difference(lastSampleTime!).inMilliseconds;
      final rate = 1000.0 * 500 / elapsedMs;

      setState(() {
        samplingRateText =
            "Sampling Rate: ${rate.toStringAsFixed(2)} Hz";
      });

      lastSampleTime = timestamp;
    } else if (lastSampleTime == null) {
      lastSampleTime = timestamp;
    }
  }

  // ==============================
  // Rep Detection
  // ==============================
  void detectRep(double magnitude, DateTime now) {
    if (magnitude > repThreshold &&
        !isRepInProgress &&
        lastMagnitude <= repThreshold) {
      isRepInProgress = true;
    } else if (magnitude <= repThreshold && isRepInProgress) {
      currentReps++;
      isRepInProgress = false;
      lastRepTime = now;
    }

    if (lastRepTime != null &&
        now.difference(lastRepTime!).inMilliseconds >
            setRestThreshold &&
        currentReps > 0) {
      currentSets++;
      currentReps = 0;
      lastRepTime = null;
    }

    lastMagnitude = magnitude;
  }

  // ==============================
  // Save CSV
  // ==============================
  Future<void> saveSessionLog() async {
    final filename = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Save Session"),
        content: TextField(
          controller: _filenameController,
          decoration:
              const InputDecoration(labelText: "Enter filename"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(
                  context,
                  _filenameController.text.isEmpty
                      ? "rep_session"
                      : _filenameController.text),
              child: const Text("Save")),
        ],
      ),
    );

    if (filename == null) return;

    final directory = await getExternalStorageDirectory();
    final file = File(
        "${directory!.path}/${filename}_${DateTime.now().millisecondsSinceEpoch}.csv");

    final rows = [
      ["Timestamp", "X", "Y", "Z"],
      ...allAccelData.map((e) => [
            e['timestamp'].toIso8601String(),
            e['x'],
            e['y'],
            e['z']
          ])
    ];

    await file.writeAsString(const ListToCsvConverter().convert(rows));

    await launchUrl(
      Uri.file(file.path),
      mode: LaunchMode.externalApplication,
    );

    _filenameController.clear();
  }

  // ==============================
  // UI
  // ==============================
  @override
  Widget build(BuildContext context) {
    if (!_permissionsGranted) {
      return Scaffold(
        appBar: AppBar(title: const Text("Data Acquisition")),
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
      appBar: AppBar(title: const Text("Data Acquisition")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  "Status: $statusText | Reps: $currentReps | Sets: $currentSets",
                ),
                const SizedBox(height: 8),
                Text(samplingRateText),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: maxPoints.toDouble(),
                  minY: -10,
                  maxY: 10,
                  lineBarsData: [
                    LineChartBarData(
                      spots: xData
                          .asMap()
                          .entries
                          .map((e) =>
                              FlSpot(e.key.toDouble(), e.value))
                          .toList(),
                      isCurved: true,
                      dotData: FlDotData(show: false),
                      color: Colors.red,
                    ),
                    LineChartBarData(
                      spots: yData
                          .asMap()
                          .entries
                          .map((e) =>
                              FlSpot(e.key.toDouble(), e.value))
                          .toList(),
                      isCurved: true,
                      dotData: FlDotData(show: false),
                      color: Colors.green,
                    ),
                    LineChartBarData(
                      spots: zData
                          .asMap()
                          .entries
                          .map((e) =>
                              FlSpot(e.key.toDouble(), e.value))
                          .toList(),
                      isCurved: true,
                      dotData: FlDotData(show: false),
                      color: Colors.blue,
                    ),
                  ],
                ),
              ),
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
                onPressed:
                    allAccelData.isNotEmpty ? saveSessionLog : null,
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
