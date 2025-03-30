import 'dart:async'; // Explicit import for StreamSubscription
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
      title: 'Rep Tracker App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Rep Tracker')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DataAcquisition()),
                );
              },
              child: Text('Data Acquisition'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => WorkoutTracker()),
                );
              },
              child: Text('Workout Tracker'),
            ),
          ],
        ),
      ),
    );
  }
}

class DataAcquisition extends StatefulWidget {
  @override
  _DataAcquisitionState createState() => _DataAcquisitionState();
}

class _DataAcquisitionState extends State<DataAcquisition> {
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  String accelData = "No data yet";
  static const String arduinoMacAddress = "D4:AB:D0:31:C3:3F";
  List<double> xData = [];
  List<double> yData = [];
  List<double> zData = [];
  final int maxPoints = 100; // Increased for longer view

  List<Map<String, dynamic>> allAccelData = []; // Store raw data for training
  int currentReps = 0;
  int currentSets = 0; // Track sets
  double lastMagnitude = 0;
  bool isRepInProgress = false;
  DateTime? lastRepTime;
  static const double repThreshold = 1.0; // Adjustable threshold
  static const int setRestThreshold = 5000;

  final TextEditingController _filenameController = TextEditingController();
  StreamSubscription<List<int>>? _characteristicSubscription; // Corrected type

  @override
  void initState() {
    super.initState();
    requestPermissions().then((granted) {
      if (granted) {
        startScanning();
      } else {
        if (mounted) {
          setState(() {
            accelData = "Permissions denied. Enable Bluetooth and Location.";
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _characteristicSubscription?.cancel();
    _filenameController.dispose();
    targetDevice?.disconnect();
    super.dispose();
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
        if (mounted) setState(() => accelData = "Bluetooth not supported");
        return;
      }

      print("Checking Bluetooth state...");
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      print("Bluetooth state: $state");
      if (state != BluetoothAdapterState.on) {
        if (mounted) setState(() => accelData = "Please turn on Bluetooth");
        return;
      }

      print("Starting BLE scan...");
      if (mounted) setState(() => accelData = "Scanning for Arduino...");
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 15));

      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          print("Found device: ${r.device.id}, Name: ${r.device.name}, RSSI: ${r.rssi}, "
              "Service UUIDs: ${r.advertisementData.serviceUuids}");
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
      if (mounted) setState(() => accelData = "Scan failed: $e");
    }
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      print("Connecting to ${device.id}...");
      if (mounted) setState(() => accelData = "Connecting...");
      await device.connect(timeout: Duration(seconds: 30));
      print("Connected successfully to ${device.id}");
      if (mounted) setState(() {
        targetDevice = device;
        accelData = "Connected to Arduino";
      });

      print("Discovering services...");
      List<BluetoothService> services = await device.discoverServices();
      print("Found ${services.length} services");
      for (BluetoothService service in services) {
        print("Service UUID: ${service.uuid.toString()}");
        if (service.uuid.toString() == "19b10000-e8f2-537e-4f6c-d104768a1214") {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            print("Characteristic UUID: ${characteristic.uuid.toString()}");
            if (characteristic.uuid.toString() == "19b10001-e8f2-537e-4f6c-d104768a1214") {
              targetCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              print("Notifications enabled for characteristic");
              _characteristicSubscription = characteristic.value.listen((value) {
                String data = String.fromCharCodes(value);
                processData(data);
              }, onError: (e) => print("BLE error: $e"));
            }
          }
        }
      }
    } catch (e) {
      print("Connection failed: $e");
      if (mounted) setState(() => accelData = "Connection failed: $e");
    }
  }

  void processData(String data) {
    print("Received data: $data");
    if (data == null || data.isEmpty) {
      print("Empty data received");
      return;
    }

    List<String> values = data.split(",");
    if (values.length >= 3) { // Only need x, y, z for raw data
      double x = double.tryParse(values[0]) ?? 0;
      double y = double.tryParse(values[1]) ?? 0;
      double z = double.tryParse(values[2]) ?? 0;
      DateTime timestamp = DateTime.now();
      double magnitude = sqrt(x * x + y * y + z * z);

      // Detect reps and sets based on magnitude
      detectRep(magnitude, timestamp);

      if (mounted) {
        setState(() {
          accelData = "Magnitude: $magnitude";
          xData.add(x);
          yData.add(y);
          zData.add(z);
          allAccelData.add({'timestamp': timestamp, 'x': x, 'y': y, 'z': z});
          if (xData.length > maxPoints) {
            xData.removeAt(0);
            yData.removeAt(0);
            zData.removeAt(0);
          }
        });
      }
      print("Processed: x=$x, y=$y, z=$z, magnitude=$magnitude");
    } else {
      print("Unexpected data format: $data");
      if (mounted) {
        setState(() => accelData = "Unexpected data: $data");
      }
    }
  }

  void detectRep(double magnitude, DateTime now) {
    if (magnitude > repThreshold && !isRepInProgress && (lastMagnitude <= repThreshold)) {
      isRepInProgress = true;
    } else if (magnitude <= repThreshold && isRepInProgress) {
      currentReps++;
      isRepInProgress = false;
      lastRepTime = now;
      print("Rep detected: $currentReps");
      if (mounted) {
        setState(() {});
      }
    }

    if (lastRepTime != null && now.difference(lastRepTime!).inMilliseconds > setRestThreshold && currentReps > 0) {
      currentSets++;
      if (mounted) {
        setState(() {
          print("Set completed: $currentSets sets (Data Acquisition mode)");
          currentReps = 0;
          lastRepTime = null;
        });
      }
    }

    lastMagnitude = magnitude;
  }

  Future<void> saveSessionLog() async {
    String? filename = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Save Session'),
          content: TextField(
            controller: _filenameController,
            decoration: InputDecoration(labelText: "Enter filename"),
          ),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text('Save'),
              onPressed: () {
                Navigator.of(context).pop(_filenameController.text.isNotEmpty
                    ? _filenameController.text
                    : 'rep_session');
              },
            ),
          ],
        );
      },
    );

    if (filename == null) return;

    final directory = await getExternalStorageDirectory();
    final file = File('${directory!.path}/${filename}_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv');
    
    String csv = "Accelerometer Data\n";
    csv += "Timestamp,X,Y,Z\n";
    for (var data in allAccelData) {
      csv += "${data['timestamp'].toIso8601String()},${data['x']},${data['y']},${data['z']}\n";
    }
    csv += "\n";

    await file.writeAsString(csv);

    try {
      final uri = await _getUriForFile(file);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("No app available to open the file. Saved to ${file.path}")),
          );
        }
      }
    } catch (e) {
      print("Error launching file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to open file. Saved to ${file.path}")),
        );
      }
    }

    _filenameController.clear();
  }

  Future<Uri> _getUriForFile(File file) async {
    const authority = 'com.example.imu_visualizer.fileprovider';
    final uri = Uri.parse('content://$authority/my_files/${file.path.split('/').last}');
    return uri;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Data Acquisition")),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Status: $accelData | Reps: $currentReps | Sets: $currentSets",
              style: TextStyle(fontSize: 16),
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
                onPressed: allAccelData.isNotEmpty ? () async {
                  await saveSessionLog();
                } : null,
                child: Text("Save Session"),
              ),
            ],
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }
}

class WorkoutTracker extends StatefulWidget {
  @override
  _WorkoutTrackerState createState() => _WorkoutTrackerState();
}

class _WorkoutTrackerState extends State<WorkoutTracker> {
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  String accelData = "No data yet";
  static const String arduinoMacAddress = "D4:AB:D0:31:C3:3F";

  static const List<String> exercises = [
    "Squat",
    "RomanianDeadlift",
    "BarbellRows",
    "BicepCurl",
    "NoExercice"
  ];
  Map<String, Map<String, int>> exerciseStats = {
    "Squat": {"reps": 0, "sets": 0},
    "RomanianDeadlift": {"reps": 0, "sets": 0},
    "BarbellRows": {"reps": 0, "sets": 0},
    "BicepCurl": {"reps": 0, "sets": 0},
    "NoExercice": {"reps": 0, "sets": 0},
  };
  String currentExercise = "None";
  int currentReps = 0;
  double lastMagnitude = 0;
  bool isRepInProgress = false;
  DateTime? lastRepTime;
  static const double repThreshold = 1.0;
  static const int setRestThreshold = 5000;

  StreamSubscription<List<int>>? _characteristicSubscription; // Corrected type

  @override
  void initState() {
    super.initState();
    requestPermissions().then((granted) {
      if (granted) {
        startScanning();
      } else {
        if (mounted) {
          setState(() {
            accelData = "Permissions denied. Enable Bluetooth and Location.";
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _characteristicSubscription?.cancel();
    targetDevice?.disconnect();
    super.dispose();
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
        if (mounted) setState(() => accelData = "Bluetooth not supported");
        return;
      }

      print("Checking Bluetooth state...");
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      print("Bluetooth state: $state");
      if (state != BluetoothAdapterState.on) {
        if (mounted) setState(() => accelData = "Please turn on Bluetooth");
        return;
      }

      print("Starting BLE scan...");
      if (mounted) setState(() => accelData = "Scanning for Arduino...");
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 15));

      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          print("Found device: ${r.device.id}, Name: ${r.device.name}, RSSI: ${r.rssi}, "
              "Service UUIDs: ${r.advertisementData.serviceUuids}");
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
      if (mounted) setState(() => accelData = "Scan failed: $e");
    }
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      print("Connecting to ${device.id}...");
      if (mounted) setState(() => accelData = "Connecting...");
      await device.connect(timeout: Duration(seconds: 30));
      print("Connected successfully to ${device.id}");
      if (mounted) setState(() {
        targetDevice = device;
        accelData = "Connected to Arduino";
      });

      print("Discovering services...");
      List<BluetoothService> services = await device.discoverServices();
      print("Found ${services.length} services");
      for (BluetoothService service in services) {
        print("Service UUID: ${service.uuid.toString()}");
        if (service.uuid.toString() == "19b10000-e8f2-537e-4f6c-d104768a1214") {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            print("Characteristic UUID: ${characteristic.uuid.toString()}");
            if (characteristic.uuid.toString() == "19b10001-e8f2-537e-4f6c-d104768a1214") {
              targetCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              print("Notifications enabled for characteristic");
              _characteristicSubscription = characteristic.value.listen((value) {
                String data = String.fromCharCodes(value);
                processData(data);
              }, onError: (e) => print("BLE error: $e"));
            }
          }
        }
      }
    } catch (e) {
      print("Connection failed: $e");
      if (mounted) setState(() => accelData = "Connection failed: $e");
    }
  }

  void processData(String data) {
    print("Received data: $data");
    if (data == null || data.isEmpty) {
      print("Empty data received");
      return;
    }

    List<String> values = data.split(",");
    if (values.length == 4 && values[3].startsWith("exercise:")) {
      double x = double.tryParse(values[0]) ?? 0;
      double y = double.tryParse(values[1]) ?? 0;
      double z = double.tryParse(values[2]) ?? 0;
      String exercise = values[3].split(":")[1].trim();
      if (exercise.endsWith("Deadli")) exercise = "RomanianDeadlift";
      DateTime now = DateTime.now();

      double magnitude = sqrt(x * x + y * y + z * z);
      detectRep(exercise, magnitude, now);

      if (mounted) {
        setState(() {
          accelData = "Current Exercise: $exercise | Magnitude: $magnitude";
          currentExercise = exercise;
        });
      }
      print("Processed: x=$x, y=$y, z=$z, magnitude=$magnitude, exercise=$exercise");
    } else {
      print("Unexpected data format: $data");
      if (mounted) {
        setState(() => accelData = "Unexpected data: $data");
      }
    }
  }

  void detectRep(String exercise, double magnitude, DateTime now) {
    if (magnitude > repThreshold && !isRepInProgress && (lastMagnitude <= repThreshold)) {
      isRepInProgress = true;
    } else if (magnitude <= repThreshold && isRepInProgress) {
      currentReps++;
      isRepInProgress = false;
      lastRepTime = now;
      print("Rep detected: $currentReps for $exercise");
      if (mounted) {
        setState(() {
          exerciseStats[exercise]?["reps"] = currentReps ?? 0;
        });
      }
    }

    if (lastRepTime != null && now.difference(lastRepTime!).inMilliseconds > setRestThreshold && currentReps > 0) {
      if (mounted) {
        setState(() {
          exerciseStats[exercise]?["sets"] = (exerciseStats[exercise]?["sets"] ?? 0) + 1;
          exerciseStats[exercise]?["reps"] = 0;
          currentReps = 0;
          lastRepTime = null;
          print("Set completed: ${exerciseStats[exercise]?["sets"] ?? 0} sets for $exercise");
        });
      }
    }

    lastMagnitude = magnitude;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Workout Tracker")),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Status: $accelData", style: TextStyle(fontSize: 16)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                String exercise = exercises[index];
                int reps = exerciseStats[exercise]?["reps"] ?? 0;
                int sets = exerciseStats[exercise]?["sets"] ?? 0;
                return ListTile(
                  title: Text(exercise),
                  subtitle: Text("Sets: $sets, Reps: $reps"),
                );
              },
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
            ],
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }
}