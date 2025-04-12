import 'dart:async'; // Explicit import for StreamSubscription
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
//import 'package:downloads_path_provider/downloads_path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:csv/csv.dart';

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
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ClassificationTesting()),
                );
              },
              child: Text('Classification Testing'),
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
  final int maxPoints = 100;

  List<Map<String, dynamic>> allAccelData = [];
  int currentReps = 0;
  int currentSets = 0;
  double lastMagnitude = 0;
  bool isRepInProgress = false;
  DateTime? lastRepTime;
  static const double repThreshold = 1.0;
  static const int setRestThreshold = 5000;

  int sampleCount = 0; // For measuring sampling rate
  DateTime? lastSampleTime; // For measuring sampling rate
  String samplingRateText = "Sampling Rate: N/A"; // Display sampling rate

  final TextEditingController _filenameController = TextEditingController();
  StreamSubscription<List<int>>? _characteristicSubscription;

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
            } else if (characteristic.uuid.toString() == "19b10002-e8f2-537e-4f6c-d104768a1214") {
              await characteristic.write("DATA_ACQUISITION".codeUnits);
              print("Set mode to DATA_ACQUISITION");
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
    if (values.length >= 3) {
      double x = double.tryParse(values[0]) ?? 0;
      double y = double.tryParse(values[1]) ?? 0;
      double z = double.tryParse(values[2]) ?? 0;
      DateTime timestamp = DateTime.now();
      double magnitude = sqrt(x * x + y * y + z * z);

      // Measure sampling rate every 500 samples for better accuracy
      sampleCount++;
      if (lastSampleTime != null) {
        if (sampleCount % 500 == 0) {
          int elapsedTime = timestamp.difference(lastSampleTime!).inMilliseconds;
          double samplingRate = 1000.0 * 500 / elapsedTime; // Hz
          setState(() {
            samplingRateText = "Sampling Rate: ${samplingRate.toStringAsFixed(2)} Hz";
          });
          print("Actual Sampling Rate (last 500 samples): $samplingRate Hz");
          lastSampleTime = timestamp;
        }
      } else {
        lastSampleTime = timestamp;
      }

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
            child: Column(
              children: [
                Text(
                  "Status: $accelData | Reps: $currentReps | Sets: $currentSets",
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(samplingRateText, style: TextStyle(fontSize: 14)),
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



// Main WorkoutTracker class
class WorkoutTracker extends StatefulWidget {
  @override
  _WorkoutTrackerState createState() => _WorkoutTrackerState();
}

class _WorkoutTrackerState extends State<WorkoutTracker> {
  // Bluetooth and Device Variables
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  String accelData = "No data yet";
  static const String arduinoMacAddress = "D4:AB:D0:31:C3:3F";
  StreamSubscription<List<int>>? _characteristicSubscription;

  // Exercise and Stats Variables
  static const List<String> exercises = [
    "Squat",
    "Deadlift",
    "BarbellRows",
    "BicepCurl",
    "NoExercice",
    "unknown"
  ];
  Map<String, Map<String, int>> exerciseStats = {
    "Squat": {"reps": 0, "sets": 0},
    "Deadlift": {"reps": 0, "sets": 0},
    "BarbellRows": {"reps": 0, "sets": 0},
    "BicepCurl": {"reps": 0, "sets": 0},
    "NoExercice": {"reps": 0, "sets": 0},
    "unknown": {"reps": 0, "sets": 0},
  };
  String currentExercise = "None";
  int currentReps = 0;
  int currentSets = 0;

  // Rep Detection Variables
  DateTime? lastRepTime;
  DateTime? lastRepDetectionTime; // For debouncing
  DateTime? lastIdleTime; // Track the last time the user was in Idle
  DateTime? lastSetTime; // Track the last time a set was completed
  bool isIdle = true; // Start in Idle state
  static const int setRestThreshold = 5000; // 5 seconds
  static const int minRepInterval = 1500; // As per your testing
  static const int transitionDelay = 1000; // 1 second delay for both transitions
  static const double zBaseline = -9.65; // Baseline Z-axis value when at rest

  // Smoothing and Idle Detection Variables
  List<double> zWindow = [];
  static const int smoothingWindowSize = 5; // Average over 5 samples (100 ms at 50 Hz)
  List<double> idleWindow = [];
  static const int idleWindowSize = 100; // 2 seconds at 50 Hz (50 samples/sec * 2 sec)
  static const double idleZThreshold = 0.1; // Max deviation for Idle (0.1 g)

  // Peak Detection Variables
  double? lastZ;
  double? lastSmoothedZ;
  bool isMovingUp = false;
  bool isMovingDown = false;
  static const double zThreshold = 0.5; // Threshold for significant Z-axis movement (after normalization)

  // Session Data Logging Variables
  List<List<dynamic>> sessionData = [];
  bool isSessionStarted = false;
  int setStartIndex = 1; // Index in sessionData where the current set starts (after header row)
  Map<String, int> exerciseCounts = {}; // Track exercise classifications during a set

  @override
  void initState() {
    super.initState();
    // Initialize session data with headers
    sessionData.add([
      "Timestamp",
      "Raw Z",
      "Normalized Z",
      "Smoothed Z",
      "Rep Detected",
      "isIdle",
      "Current Reps",
      "Current Sets",
      "Exercise" // New column for classified exercise
    ]);
    // Initialize exercise counts
    for (String exercise in exercises) {
      exerciseCounts[exercise] = 0;
    }
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

  // Permission Handling
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

  // Bluetooth Scanning and Connection
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
            } else if (characteristic.uuid.toString() == "19b10002-e8f2-537e-4f6c-d104768a1214") {
              await characteristic.write("WORKOUT_TRACKER".codeUnits);
              print("Set mode to WORKOUT_TRACKER");
            }
          }
        }
      }
    } catch (e) {
      print("Connection failed: $e");
      if (mounted) setState(() => accelData = "Connection failed: $e");
    }
  }

  // Data Processing and Rep Detection
  void processData(String data) {
    print("Received data: $data");
    if (data == null || data.isEmpty) {
      print("Empty data received");
      return;
    }

    List<String> values = data.split(",");
    if (values.length == 3) {
      // Raw data format: x,y,z
      double x = double.tryParse(values[0]) ?? 0;
      double y = double.tryParse(values[1]) ?? 0;
      double z = double.tryParse(values[2]) ?? 0;
      DateTime now = DateTime.now();
      detectRep(z, now, "unknown"); // Default to "unknown" if no classification
      if (mounted) {
        setState(() {
          accelData = "Current Exercise: $currentExercise | Z: $z | Reps: $currentReps | Sets: $currentSets";
        });
      }
      print("Processed raw: x=$x, y=$y, z=$z");
    } else if (values.length == 4 && values[3].startsWith("exercise:")) {
      // Classified data format: x,y,z,exercise:label
      double x = double.tryParse(values[0]) ?? 0;
      double y = double.tryParse(values[1]) ?? 0;
      double z = double.tryParse(values[2]) ?? 0;
      String exercise = values[3].split(":")[1].trim();
      if (exercise.endsWith("Deadli")) exercise = "RomanianDeadlift";
      DateTime now = DateTime.now();
      detectRep(z, now, exercise);
      if (mounted) {
        setState(() {
          accelData = "Current Exercise: $exercise | Z: $z | Reps: $currentReps | Sets: $currentSets";
          currentExercise = exercise;
        });
      }
      print("Processed classified: x=$x, y=$y, z=$z, exercise=$exercise");
    } else {
      print("Unexpected data format: $data");
      if (mounted) {
        setState(() => accelData = "Unexpected data: $data");
      }
    }
  }

  void detectRep(double z, DateTime now, String classifiedExercise) {
    // Increment the count for the classified exercise
    if (exercises.contains(classifiedExercise)) {
      exerciseCounts[classifiedExercise] = (exerciseCounts[classifiedExercise] ?? 0) + 1;
    } else {
      exerciseCounts["unknown"] = (exerciseCounts["unknown"] ?? 0) + 1;
    }

    // Normalize the Z-axis data by subtracting the baseline
    double normalizedZ = z - zBaseline;

    // Check for Idle state based on Z-axis data
    idleWindow.add(normalizedZ);
    if (idleWindow.length > idleWindowSize) {
      idleWindow.removeAt(0);
    }
    if (idleWindow.length == idleWindowSize) {
      double zMin = idleWindow.reduce((a, b) => a < b ? a : b);
      double zMax = idleWindow.reduce((a, b) => a > b ? a : b);
      if (zMax - zMin < idleZThreshold) {
        isIdle = true;
        lastIdleTime = now;
      } else {
        isIdle = false;
      }
    }

    // Smooth the normalized Z-axis data
    zWindow.add(normalizedZ);
    if (zWindow.length > smoothingWindowSize) {
      zWindow.removeAt(0);
    }
    double smoothedZ = zWindow.reduce((a, b) => a + b) / zWindow.length;

    // Debouncing: Ensure at least minRepInterval ms between rep detections
    if (lastRepDetectionTime != null &&
        now.difference(lastRepDetectionTime!).inMilliseconds < minRepInterval) {
      // Log data even if rep is not detected due to debouncing
      sessionData.add([
        now.toIso8601String(),
        z,
        normalizedZ,
        smoothedZ,
        0, // No rep detected
        isIdle ? 1 : 0,
        currentReps,
        currentSets,
        "" // Exercise will be filled in later
      ]);
      lastZ = z;
      lastSmoothedZ = smoothedZ;
      return;
    }

    // Ignore reps during the transition period from Idle to Exercise
    if (lastIdleTime != null &&
        !isIdle &&
        now.difference(lastIdleTime!).inMilliseconds < transitionDelay) {
      print("Ignoring rep during Idle-to-Exercise transition");
      sessionData.add([
        now.toIso8601String(),
        z,
        normalizedZ,
        smoothedZ,
        0, // No rep detected
        isIdle ? 1 : 0,
        currentReps,
        currentSets,
        ""
      ]);
      lastZ = z;
      lastSmoothedZ = smoothedZ;
      return;
    }

    // Ignore reps during the transition period after a set is completed
    if (lastSetTime != null &&
        now.difference(lastSetTime!).inMilliseconds < transitionDelay) {
      print("Ignoring rep during Exercise-to-Idle transition");
      sessionData.add([
        now.toIso8601String(),
        z,
        normalizedZ,
        smoothedZ,
        0, // No rep detected
        isIdle ? 1 : 0,
        currentReps,
        currentSets,
        ""
      ]);
      lastZ = z;
      lastSmoothedZ = smoothedZ;
      return;
    }

    bool repDetected = false;

    // Detect peaks in normalized Z-axis data
    if (lastSmoothedZ != null && lastZ != null) {
      double zDelta = smoothedZ - lastSmoothedZ!;
      bool isMovingUpNow = zDelta > 0;
      bool isMovingDownNow = zDelta < 0;

      // Detect a rep at the peak: when transitioning from moving up to moving down, and the value is above zThreshold
      if (isMovingUp && !isMovingUpNow && smoothedZ > zThreshold) {
        currentReps++;
        lastRepTime = now;
        lastRepDetectionTime = now;
        repDetected = true;
        print("Rep detected at peak: $currentReps");
        if (mounted) {
          setState(() {});
        }
      }

      // Update movement direction
      if (isMovingUpNow && smoothedZ > -zThreshold) {
        isMovingUp = true;
      } else if (isMovingDownNow && smoothedZ < zThreshold) {
        isMovingDown = true;
      } else {
        isMovingUp = false;
        isMovingDown = false;
      }
    }

    // Log the data point
    sessionData.add([
      now.toIso8601String(),
      z,
      normalizedZ,
      smoothedZ,
      repDetected ? 1 : 0, // 1 if rep detected, 0 otherwise
      isIdle ? 1 : 0,
      currentReps,
      currentSets,
      "" // Exercise will be filled in later
    ]);

    // Detect set completion
    if (lastRepTime != null && now.difference(lastRepTime!).inMilliseconds > setRestThreshold && currentReps > 0) {
      // Classify the set based on the most frequent exercise
      String setExercise = classifySet();
      print("Set classified as: $setExercise");

      // Update the sessionData rows for this set with the classified exercise
      for (int i = setStartIndex; i < sessionData.length; i++) {
        sessionData[i][8] = setExercise; // Update the "Exercise" column
      }

      // Update exercise stats
      if (exerciseStats.containsKey(setExercise)) {
        exerciseStats[setExercise]!["reps"] = (exerciseStats[setExercise]!["reps"] ?? 0) + currentReps;
        exerciseStats[setExercise]!["sets"] = (exerciseStats[setExercise]!["sets"] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          currentSets++;
          currentReps = 0;
          lastRepTime = null;
          lastSetTime = now; // Record the time the set was completed
          print("Set completed: $currentSets sets");
        });
      }

      // Reset for the next set
      setStartIndex = sessionData.length;
      exerciseCounts.clear();
      for (String exercise in exercises) {
        exerciseCounts[exercise] = 0;
      }
    }

    lastZ = z;
    lastSmoothedZ = smoothedZ;
  }

  // Set Classification Logic
  String classifySet() {
    // Find the exercise with the highest count, ignoring "NoExercice" and "unknown" if they are the highest
    String mostFrequentExercise = "unknown";
    int maxCount = 0;

    // First, find the exercise with the highest count
    exerciseCounts.forEach((exercise, count) {
      if (count > maxCount) {
        mostFrequentExercise = exercise;
        maxCount = count;
      }
    });

    // If "NoExercice" or "unknown" has the highest count, find the next most frequent exercise
    if (mostFrequentExercise == "NoExercice" || mostFrequentExercise == "unknown") {
      mostFrequentExercise = "unknown";
      maxCount = 0;
      exerciseCounts.forEach((exercise, count) {
        if (exercise != "NoExercice" && exercise != "unknown" && count > maxCount) {
          mostFrequentExercise = exercise;
          maxCount = count;
        }
      });
    }

    // If no valid exercise was found (e.g., all counts are 0 except for "NoExercice" or "unknown"), default to "unknown"
    if (maxCount == 0) {
      mostFrequentExercise = "unknown";
    }

    return mostFrequentExercise;
  }

  // CSV Export
Future<void> exportToCsv() async {
  try {
    // Get the external storage directory (e.g., Downloads on Android)
    final directory = await getExternalStorageDirectory();
    if (directory == null) {
      if (mounted) {
        setState(() {
          accelData = "Error: Could not access storage directory";
        });
      }
      return;
    }

    // Create a unique filename with timestamp
    final timestamp = DateTime.now().toIso8601String().replaceAll(":", "-").replaceAll(".", "-");
    final filePath = "${directory.path}/workout_session_$timestamp.csv";
    final file = File(filePath);

    // Convert session data to CSV string
    final csvConverter = ListToCsvConverter(); // Remove 'const' and instantiate normally
    String csv = csvConverter.convert(sessionData);

    // Write the CSV file
    await file.writeAsString(csv);
    print("CSV file saved to: $filePath");

    if (mounted) {
      setState(() {
        accelData = "CSV exported to: $filePath";
      });
    }
  } catch (e) {
    print("Error exporting CSV: $e");
    if (mounted) {
      setState(() {
        accelData = "Error exporting CSV: $e";
      });
    }
  }
}

  // UI
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
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Total Reps: $currentReps | Total Sets: $currentSets", style: TextStyle(fontSize: 16)),
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
              SizedBox(width: 16),
              ElevatedButton(
                onPressed: exportToCsv,
                child: Text("Export CSV"),
              ),
            ],
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }
}


class ClassificationTesting extends StatefulWidget {
  @override
  _ClassificationTestingState createState() => _ClassificationTestingState();
}

class _ClassificationTestingState extends State<ClassificationTesting> {
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  String statusText = "No data yet";
  static const String arduinoMacAddress = "D4:AB:D0:31:C3:3F";

  // List of possible exercises and their counts
  static const List<String> exercises = [
    "Squat",
    "RomanianDeadlift",
    "BarbellRows",
    "BicepCurl",
    "NoExercice",
    "Unknown",
  ];
  Map<String, int> classificationCounts = {
    "Squat": 0,
    "RomanianDeadlift": 0,
    "BarbellRows": 0,
    "BicepCurl": 0,
    "NoExercice": 0,
    "Unknown": 0,
  };

  StreamSubscription<List<int>>? _characteristicSubscription;

  @override
  void initState() {
    super.initState();
    requestPermissions().then((granted) {
      if (granted) {
        startScanning();
      } else {
        if (mounted) {
          setState(() {
            statusText = "Permissions denied. Enable Bluetooth and Location.";
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
        if (mounted) setState(() => statusText = "Bluetooth not supported");
        return;
      }

      print("Checking Bluetooth state...");
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      print("Bluetooth state: $state");
      if (state != BluetoothAdapterState.on) {
        if (mounted) setState(() => statusText = "Please turn on Bluetooth");
        return;
      }

      print("Starting BLE scan...");
      if (mounted) setState(() => statusText = "Scanning for Arduino...");
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
      if (mounted) setState(() => statusText = "Scan failed: $e");
    }
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      print("Connecting to ${device.id}...");
      if (mounted) setState(() => statusText = "Connecting...");
      await device.connect(timeout: Duration(seconds: 30));
      print("Connected successfully to ${device.id}");
      if (mounted) setState(() {
        targetDevice = device;
        statusText = "Connected to Arduino";
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
            } else if (characteristic.uuid.toString() == "19b10002-e8f2-537e-4f6c-d104768a1214") {
              await characteristic.write("WORKOUT_TRACKER".codeUnits);
              print("Set mode to WORKOUT_TRACKER");
            }
          }
        }
      }
    } catch (e) {
      print("Connection failed: $e");
      if (mounted) setState(() => statusText = "Connection failed: $e");
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
      // Classified data format: x,y,z,exercise:label
      String exercise = values[3].split(":")[1].trim();
      if (exercise.endsWith("Deadli")) exercise = "RomanianDeadlift";
      if (mounted) {
        setState(() {
          statusText = "Received Classification: $exercise";
          classificationCounts[exercise] = (classificationCounts[exercise] ?? 0) + 1;
        });
      }
      print("Processed classified: exercise=$exercise");
    } else {
      print("Unexpected data format: $data");
      if (mounted) {
        setState(() => statusText = "Unexpected data: $data");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Classification Testing")),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Status: $statusText", style: TextStyle(fontSize: 16)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                String exercise = exercises[index];
                int count = classificationCounts[exercise] ?? 0;
                return ListTile(
                  title: Text(exercise),
                  trailing: Text("Count: $count"),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: targetDevice != null ? () => targetDevice!.disconnect() : null,
              child: Text("Disconnect"),
            ),
          ),
        ],
      ),
    );
  }
}