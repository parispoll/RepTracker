import 'package:flutter/material.dart';

import 'DataAcquisition.dart';
import 'ClassificationTesting.dart';
import 'workout_tracker.dart';
import 'session_log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rep Tracker App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rep Tracker')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _navButton(
              context,
              label: 'Data Acquisition',
              page: DataAcquisition(),
            ),
            const SizedBox(height: 20),
            _navButton(
              context,
              label: 'Workout Tracker',
              page: WorkoutTracker(),
            ),
            const SizedBox(height: 20),
            _navButton(
              context,
              label: 'Classification Testing',
              page: ClassificationTesting(),
            ),
            const SizedBox(height: 20),
            _navButton(
              context,
              label: 'Session Log',
              page: const SessionLog(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navButton(
    BuildContext context, {
    required String label,
    required Widget page,
  }) {
    return ElevatedButton(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => page),
        );
      },
      child: Text(label),
    );
  }
}
