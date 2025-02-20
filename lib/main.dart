import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: AccelerometerVisualizer(),
    );
  }
}

class AccelerometerVisualizer extends StatefulWidget {
  @override
  _AccelerometerVisualizerState createState() => _AccelerometerVisualizerState();
}

class _AccelerometerVisualizerState extends State<AccelerometerVisualizer> {
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? targetCharacteristic;
  String accelData = "No data yet";
  static const String arduinoMacAddress = "D4:AB:D0:31:C3:3F";
  List<double> xData = [];
  List<double> yData = [];
  List<double> zData = [];
  final int maxPoints = 50;

  @override
  void initState() {
    super.initState();
    requestPermissions().then((granted) {
      if (granted) {
        startScanning();
      } else {
        setState(() {
          accelData = "Permissions denied. Enable Bluetooth and Location in Settings.";
        });
      }
    });
  }

  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = statuses[Permission.bluetoothScan]!.isGranted &&
        statuses[Permission.bluetoothConnect]!.isGranted &&
        statuses[Permission.location]!.isGranted;

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
                updateGraph(data);
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

  void updateGraph(String data) {
    List<String> values = data.split(",");
    if (values.length == 3) {
      double x = double.tryParse(values[0]) ?? 0;
      double y = double.tryParse(values[1]) ?? 0;
      double z = double.tryParse(values[2]) ?? 0;

      setState(() {
        accelData = data;
        xData.add(x);
        yData.add(y);
        zData.add(z);
        if (xData.length > maxPoints) {
          xData.removeAt(0);
          yData.removeAt(0);
          zData.removeAt(0);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Accelerometer Visualizer")),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Latest Data: $accelData", style: TextStyle(fontSize: 16)),
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
                  minY: -2,
                  maxY: 2,
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
          ElevatedButton(
            onPressed: targetDevice != null ? () => targetDevice!.disconnect() : null,
            child: Text("Disconnect"),
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