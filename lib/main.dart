import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: RepTracker(),
    );
  }
}

class RepTracker extends StatefulWidget {
  @override
  _RepTrackerState createState() => _RepTrackerState();
}

class _RepTrackerState extends State<RepTracker> {
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  String accelData = "No data yet";
  static const String arduinoMacAddress = "D4:AB:D0:31:C3:3F";
  List<double> xData = [];
  List<double> yData = [];
  List<double> zData = [];
  final int maxPoints = 50;

  int repCount = 0;
  int setCount = 0;
  List<int> repsPerSet = [];
  double lastMagnitude = 0;
  bool isRepInProgress = false;
  DateTime? lastRepTime;
  static const double repThreshold = 1.5;
  static const int setRestThreshold = 5000;

  // Store all accelerometer data with timestamps
  List<Map<String, dynamic>> allAccelData = [];

  @override
  void initState() {
    super.initState();
    requestPermissions().then((granted) {
      if (granted) {
        startScanning();
      } else {
        setState(() {
          accelData = "Permissions denied. Enable Bluetooth and Location.";
        });
      }
    });
  }

  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.storage,
    ].request();

    bool allGranted = statuses[Permission.bluetoothScan]!.isGranted &&
        statuses[Permission.bluetoothConnect]!.isGranted &&
        statuses[Permission.location]!.isGranted &&
        statuses[Permission.storage]!.isGranted;

    if (!allGranted) {
      print("Permissions status: $statuses");
      openAppSettings();
    }
    return allGranted;
  }

  void startScanning() async {
    try {
      print("Checking Bluetooth support...");
      if (!await FlutterBluePlus.isSupported) {
        setState(() => accelData = "Bluetooth not supported");
        return;
      }

      print("Checking Bluetooth state...");
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        setState(() => accelData = "Please turn on Bluetooth");
        return;
      }

      print("Starting BLE scan...");
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 15));

      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.id.toString().toUpperCase() == arduinoMacAddress.toUpperCase()) {
            print("Found Arduino at $arduinoMacAddress! Connecting...");
            FlutterBluePlus.stopScan();
            connectToDevice(r.device);
            break;
          }
        }
      }, onError: (e) => print("Scan error: $e"));

      await Future.delayed(Duration(seconds: 15));
      if (FlutterBluePlus.isScanningNow) {
        print("Stopping scan manually...");
        await FlutterBluePlus.stopScan();
        if (targetDevice == null) {
          print("No Arduino found, retrying scan...");
          startScanning();
        }
      }
    } catch (e) {
      print("Scanning failed: $e");
      setState(() => accelData = "Scan failed: $e");
    }
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      print("Connecting to ${device.id}...");
      await device.connect();
      setState(() {
        targetDevice = device;
        accelData = "Connected to Arduino";
      });

      print("Discovering services...");
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid.toString() == "19b10000-e8f2-537e-4f6c-d104768a1214") {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == "19b10001-e8f2-537e-4f6c-d104768a1214") {
              targetCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              characteristic.value.listen((value) {
                String data = String.fromCharCodes(value);
                processData(data);
              });
            }
          }
        }
      }
    } catch (e) {
      print("Connection failed: $e");
      setState(() => accelData = "Connection failed: $e");
    }
  }

  void processData(String data) {
    List<String> values = data.split(",");
    if (values.length == 3) {
      double x = double.tryParse(values[0]) ?? 0;
      double y = double.tryParse(values[1]) ?? 0;
      double z = double.tryParse(values[2]) ?? 0;
      DateTime timestamp = DateTime.now();

      double magnitude = sqrt(x * x + y * y + z * z);
      detectRep(magnitude);

      setState(() {
        accelData = data;
        xData.add(x);
        yData.add(y);
        zData.add(z);
        allAccelData.add({'timestamp': timestamp, 'x': x, 'y': y, 'z': z}); // Store all data
        if (xData.length > maxPoints) {
          xData.removeAt(0);
          yData.removeAt(0);
          zData.removeAt(0);
        }
      });
    }
  }

  void detectRep(double magnitude) {
    DateTime now = DateTime.now();

    if (magnitude > repThreshold && !isRepInProgress && (lastMagnitude <= repThreshold)) {
      isRepInProgress = true;
    } else if (magnitude <= repThreshold && isRepInProgress) {
      repCount++;
      isRepInProgress = false;
      lastRepTime = now;
      print("Rep detected: $repCount in current set");
    }

    if (lastRepTime != null && now.difference(lastRepTime!).inMilliseconds > setRestThreshold && repCount > 0) {
      setState(() {
        repsPerSet.add(repCount);
        setCount++;
        repCount = 0;
        lastRepTime = null;
        print("Set completed: $setCount sets, last set had ${repsPerSet.last} reps");
      });
    }

    lastMagnitude = magnitude;
  }

  Future<void> saveSessionLog() async {
    final directory = await getExternalStorageDirectory();
    final file = File('${directory!.path}/rep_session_${DateTime.now().toIso8601String()}.csv');
    
    // Build CSV content
    String csv = "Accelerometer Data\n";
    csv += "Timestamp,X,Y,Z\n";
    for (var data in allAccelData) {
      csv += "${data['timestamp'].toIso8601String()},${data['x']},${data['y']},${data['z']}\n";
    }
    csv += "\n"; // Blank line to separate sections
    csv += "Reps and Sets Summary\n";
    csv += "Set,Reps\n";
    for (int i = 0; i < repsPerSet.length; i++) {
      csv += "${i + 1},${repsPerSet[i]}\n";
    }
    csv += "Total Sets: $setCount, Total Reps: ${repsPerSet.isEmpty ? repCount : repsPerSet.reduce((a, b) => a + b) + repCount}\n";

    await file.writeAsString(csv);

    // Open the specific file
    final Uri fileUri = Uri.file(file.path);
    try {
      if (await canLaunchUrl(fileUri)) {
        await launchUrl(
          fileUri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No app available to open the file. Saved to ${file.path}")),
        );
      }
    } catch (e) {
      print("Error launching file: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to open file. Saved to ${file.path}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Rep Tracker")),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text("Status: $accelData", style: TextStyle(fontSize: 16)),
                SizedBox(height: 8),
                Text("Current Set: $setCount"),
                Text("Reps in Current Set: $repCount"),
                Text("Total Reps: ${repsPerSet.isEmpty ? repCount : repsPerSet.reduce((a, b) => a + b) + repCount}"),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(show: true),
                  borderData: FlBorderData(show: true),
                  minX: 0,
                  maxX: maxPoints.toDouble(),
                  minY: -10,
                  maxY: 10,
                  lineBarsData: [
                    LineChartBarData(
                      spots: xData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                      isCurved: true,
                      color: Colors.red,
                      dotData: FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: yData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                      isCurved: true,
                      color: Colors.green,
                      dotData: FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: zData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                      isCurved: true,
                      color: Colors.blue,
                      dotData: FlDotData(show: false),
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
                onPressed: targetDevice != null ? () => targetDevice!.disconnect() : null,
                child: Text("Disconnect"),
              ),
              SizedBox(width: 16),
              ElevatedButton(
                onPressed: targetDevice == null ? startScanning : null,
                child: Text("Reconnect"),
              ),
              SizedBox(width: 16),
              ElevatedButton(
                onPressed: repsPerSet.isNotEmpty || repCount > 0 ? saveSessionLog : null,
                child: Text("Save Session"),
              ),
            ],
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  void dispose() {
    targetDevice?.disconnect();
    super.dispose();
  }
}