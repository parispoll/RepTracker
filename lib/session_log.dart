import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:url_launcher/url_launcher.dart';

class SessionLog extends StatefulWidget {
  const SessionLog({super.key});

  @override
  _SessionLogState createState() => _SessionLogState();
}

class _SessionLogState extends State<SessionLog> {
  Map<String, List<List<dynamic>>> savedSessions = {};
  final TextEditingController _renameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  // ==============================
  // Load / Save
  // ==============================
  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = prefs.getString('saved_sessions');

    if (sessions == null) return;

    final decoded = jsonDecode(sessions) as Map<String, dynamic>;
    setState(() {
      savedSessions = decoded.map((key, value) => MapEntry(
            key,
            (value as List<dynamic>)
                .map((row) => (row as List<dynamic>).cast<dynamic>())
                .toList(),
          ));
    });
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_sessions',
      jsonEncode(savedSessions),
    );
  }

  // ==============================
  // Delete / Rename
  // ==============================
  Future<void> _deleteSession(String name) async {
    setState(() {
      savedSessions.remove(name);
    });
    await _saveSessions();
  }

  Future<void> _renameSession(String oldName, String newName) async {
    if (newName.isEmpty || savedSessions.containsKey(newName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Session name cannot be empty or already exists"),
        ),
      );
      return;
    }

    setState(() {
      final data = savedSessions.remove(oldName)!;
      savedSessions[newName] = data;
    });

    await _saveSessions();
  }

  // ==============================
  // CSV Export (Android 13+ SAFE)
  // ==============================
  Future<void> _exportSessionToCsv(
    String sessionName,
    List<List<dynamic>> sessionData,
  ) async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        throw Exception("Storage unavailable");
      }

      final file = File(
        "${directory.path}/$sessionName.csv",
      );

      final csv = const ListToCsvConverter().convert(sessionData);
      await file.writeAsString(csv);

      await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Export failed: $e")),
      );
    }
  }

  // ==============================
  // Session Details Dialog
  // ==============================
  void _showSessionDetails(
    String sessionName,
    List<List<dynamic>> sessionData,
  ) {
    final Map<String, Map<String, int>> exerciseStats = {};

    for (final row in sessionData.skip(1)) {
      final exercise = row[8] as String;
      final reps = row[6] as int;
      final sets = row[7] as int;

      if (exercise.isEmpty || reps <= 0) continue;

      exerciseStats.putIfAbsent(
        exercise,
        () => {"reps": 0, "sets": 0},
      );

      if (sets > exerciseStats[exercise]!["sets"]!) {
        exerciseStats[exercise]!["reps"] =
            exerciseStats[exercise]!["reps"]! + reps;
        exerciseStats[exercise]!["sets"] = sets;
      }
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(sessionName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Exercises Performed:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (exerciseStats.isEmpty)
                const Text("No exercises recorded."),
              ...exerciseStats.entries.map(
                (e) => Text(
                  "${e.key}: ${e.value['sets']} sets, ${e.value['reps']} reps",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _renameController.text = sessionName;
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Rename Session"),
                  content: TextField(
                    controller: _renameController,
                    decoration: const InputDecoration(
                      hintText: "Enter new name",
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _renameSession(
                          sessionName,
                          _renameController.text,
                        );
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      child: const Text("Rename"),
                    ),
                  ],
                ),
              );
            },
            child: const Text("Rename"),
          ),
          TextButton(
            onPressed: () =>
                _exportSessionToCsv(sessionName, sessionData),
            child: const Text("Export CSV"),
          ),
          TextButton(
            onPressed: () {
              _deleteSession(sessionName);
              Navigator.pop(context);
            },
            child:
                const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  // ==============================
  // UI
  // ==============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Session Log")),
      body: savedSessions.isEmpty
          ? const Center(child: Text("No saved sessions yet."))
          : ListView.builder(
              itemCount: savedSessions.length,
              itemBuilder: (_, index) {
                final name = savedSessions.keys.elementAt(index);
                return ListTile(
                  title: Text(name),
                  onTap: () =>
                      _showSessionDetails(name, savedSessions[name]!),
                );
              },
            ),
    );
  }
}
