import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'custom_snackbar.dart';

/// Represents a single timestamped command in the recorded stream.
class RecordedCommand {
  final int offsetMs;
  final int x;
  final int y;
  final int speed;
  final double steering;

  const RecordedCommand({
    required this.offsetMs,
    required this.x,
    required this.y,
    required this.speed,
    required this.steering,
  });

  String get command =>
      'joystick,$x,$y,$speed,${steering.toStringAsFixed(1)}\n';

  Map<String, dynamic> toJson() => {
    'offsetMs': offsetMs,
    'x': x,
    'y': y,
    'speed': speed,
    'steering': steering,
  };

  factory RecordedCommand.fromJson(Map<String, dynamic> json) =>
      RecordedCommand(
        offsetMs: json['offsetMs'] as int,
        x: json['x'] as int,
        y: json['y'] as int,
        speed: json['speed'] as int,
        steering: (json['steering'] as num).toDouble(),
      );
}

/// Represents a named saved recording sequence in persistent storage.
class SavedRecording {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<RecordedCommand> commands;

  SavedRecording({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.commands,
  });

  int get durationMs => commands.isNotEmpty ? commands.last.offsetMs : 0;
  double get durationSeconds => durationMs / 1000.0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'commands': commands.map((c) => c.toJson()).toList(),
  };

  factory SavedRecording.fromJson(Map<String, dynamic> json) => SavedRecording(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    commands: (json['commands'] as List<dynamic>)
        .map((c) => RecordedCommand.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}

/// Controller that records and plays back the exact stream of joystick commands with 1:1 real-time timing.
class JoystickRecorder extends ChangeNotifier {
  final List<RecordedCommand> _commands = [];
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _hasStartedFirstMovement = false;

  Stopwatch? _recordingStopwatch;
  bool _cancelPlaybackRequested = false;

  List<RecordedCommand> get commands => List.unmodifiable(_commands);
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  bool get hasRecording => _commands.isNotEmpty;

  JoystickRecorder() {
    _loadFromPreferences();
  }

  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('recorded_stream_sequence');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        _commands.clear();
        for (final item in decoded) {
          _commands.add(RecordedCommand.fromJson(item as Map<String, dynamic>));
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String jsonStr = jsonEncode(
        _commands.map((cmd) => cmd.toJson()).toList(),
      );
      await prefs.setString('recorded_stream_sequence', jsonStr);
    } catch (_) {}
  }

  /// Arm recording mode. The stream clock starts on the first movement command.
  void startRecording() {
    _commands.clear();
    _isRecording = true;
    _isPlaying = false;
    _hasStartedFirstMovement = false;
    _recordingStopwatch = null;
    notifyListeners();
  }

  /// Records EVERY command sent to BLE while recording is active.
  void recordCommand(int x, int y, int speed, double steering) {
    if (!_isRecording) return;

    // Wait for the first non-zero movement before starting stream clock (eliminates initial idle pause)
    if (!_hasStartedFirstMovement) {
      if (x == 0 && y == 0) return;
      _hasStartedFirstMovement = true;
      _recordingStopwatch = Stopwatch()..start();
    }

    final int offset = _recordingStopwatch?.elapsedMilliseconds ?? 0;
    _commands.add(
      RecordedCommand(
        offsetMs: offset,
        x: x,
        y: y,
        speed: speed,
        steering: steering,
      ),
    );
    notifyListeners();
  }

  /// Stops current recording session and saves recorded stream.
  void stopRecording() {
    if (!_isRecording) return;
    final int totalMs =
        _recordingStopwatch?.elapsedMilliseconds ??
        (_commands.isNotEmpty ? _commands.last.offsetMs : 0);
    _isRecording = false;
    _recordingStopwatch?.stop();
    _recordingStopwatch = null;

    final int entryCount = _commands.length;
    final String jsonStr = jsonEncode(
      _commands.map((cmd) => cmd.toJson()).toList(),
    );
    final int bytes = utf8.encode(jsonStr).length;
    final double sizeInMB = bytes / (1024.0 * 1024.0);
    final double totalSeconds = totalMs / 1000.0;

    debugPrint(
      'Recording stopped: $entryCount recorded entries, ${totalSeconds.toStringAsFixed(2)}s driving time, ${sizeInMB.toStringAsFixed(4)} MB ($bytes bytes)',
    );

    _saveToPreferences();
    notifyListeners();
  }

  /// Saves current recording as a named recording in persistent storage.
  Future<void> saveNamedRecording(String name) async {
    if (_commands.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedList = await getSavedRecordings();

      final newRecording = SavedRecording(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        createdAt: DateTime.now(),
        commands: List.from(_commands),
      );

      savedList.insert(0, newRecording);

      final String jsonStr = jsonEncode(
        savedList.map((rec) => rec.toJson()).toList(),
      );
      await prefs.setString('saved_named_recordings', jsonStr);
    } catch (_) {}
  }

  /// Retrieves list of all saved named recordings.
  Future<List<SavedRecording>> getSavedRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('saved_named_recordings');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        return decoded
            .map(
              (item) => SavedRecording.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Loads a saved recording into active sequence without starting playback.
  void loadRecording(SavedRecording recording) {
    _commands.clear();
    _commands.addAll(recording.commands);
    _saveToPreferences();
    notifyListeners();
  }

  /// Deletes a saved recording from persistent storage.
  Future<void> deleteSavedRecording(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedList = await getSavedRecordings();
      savedList.removeWhere((rec) => rec.id == id);

      final String jsonStr = jsonEncode(
        savedList.map((rec) => rec.toJson()).toList(),
      );
      await prefs.setString('saved_named_recordings', jsonStr);
    } catch (_) {}
  }

  /// Plays back the exact stream of recorded commands with 1:1 real-time millisecond timing.
  Future<void> playback({
    required Function(String command) onSendCommand,
    required Function(double x, double y) onUpdatePosition,
  }) async {
    if (_commands.isEmpty || _isPlaying || _isRecording) return;

    _isPlaying = true;
    _cancelPlaybackRequested = false;
    notifyListeners();

    final Stopwatch playbackStopwatch = Stopwatch()..start();

    try {
      for (final cmd in _commands) {
        if (_cancelPlaybackRequested) break;

        // Wait until playback Stopwatch reaches exact recorded command offset
        while (playbackStopwatch.elapsedMilliseconds < cmd.offsetMs) {
          if (_cancelPlaybackRequested) break;
          final int remaining =
              cmd.offsetMs - playbackStopwatch.elapsedMilliseconds;
          final int waitMs = remaining < 10 ? remaining : 10;
          if (waitMs <= 0) break;
          await Future.delayed(Duration(milliseconds: waitMs));
        }

        if (_cancelPlaybackRequested) break;

        // Update UI joystick position and transmit BLE command immediately
        onUpdatePosition(cmd.x.toDouble(), cmd.y.toDouble());
        onSendCommand(cmd.command);
      }
    } finally {
      // Send explicit stop command to car at end of playback
      final lastCmd = _commands.isNotEmpty ? _commands.last : null;
      final speed = lastCmd?.speed ?? 50;
      final steering = lastCmd?.steering ?? 0.2;
      onSendCommand('joystick,0,0,$speed,${steering.toStringAsFixed(1)}\n');

      playbackStopwatch.stop();
      _isPlaying = false;
      _cancelPlaybackRequested = false;
      onUpdatePosition(0.0, 0.0);
      notifyListeners();
    }
  }

  /// Stops sequence playback immediately.
  void stopPlayback() {
    if (_isPlaying) {
      _cancelPlaybackRequested = true;
      notifyListeners();
    }
  }

  /// Clears stored sequence.
  void clear() {
    _commands.clear();
    _saveToPreferences();
    notifyListeners();
  }
}

/// Icon-only control bar widget placed directly under the joystick.
class RecordingControlsWidget extends StatelessWidget {
  final JoystickRecorder recorder;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onStartPlayback;
  final VoidCallback onStopPlayback;

  const RecordingControlsWidget({
    super.key,
    required this.recorder,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onStartPlayback,
    required this.onStopPlayback,
  });

  void _showSaveDialog(BuildContext context) {
    final controller = TextEditingController(
      text: 'Recording ${DateTime.now().minute}',
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save Recording'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Recording Name',
              hintText: 'e.g. Route 1',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  await recorder.saveNamedRecording(name);
                  if (context.mounted) {
                    Navigator.pop(context);
                    showAppSnackBar(context, 'Saved "$name"');
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showLoadDialog(BuildContext context) async {
    final saved = await recorder.getSavedRecordings();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Load Saved Recording'),
              content: SizedBox(
                width: double.maxFinite,
                child: saved.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Text(
                          'No saved recordings found.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: saved.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final rec = saved[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 4.0,
                            ),
                            leading: const CircleAvatar(
                              child: Icon(Icons.route, size: 20),
                            ),
                            title: Text(
                              rec.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${rec.commands.length} steps | ${rec.durationSeconds.toStringAsFixed(1)}s',
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              tooltip: 'Delete',
                              onPressed: () async {
                                await recorder.deleteSavedRecording(rec.id);
                                setDialogState(() {
                                  saved.removeAt(index);
                                });
                              },
                            ),
                            onTap: () {
                              recorder.loadRecording(rec);
                              Navigator.pop(context);
                              showAppSnackBar(
                                context,
                                'Loaded "${rec.name}". Press Play to start.',
                              );
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        final isRecording = recorder.isRecording;
        final isPlaying = recorder.isPlaying;
        final hasRecording = recorder.hasRecording;

        final accentColor = isDark
            ? const Color(0xFF00E5FF)
            : const Color(0xFF00838F);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Record / Stop Recording Button (Icon Only with Tooltip)
            IconButton.filledTonal(
              tooltip: isRecording ? 'Stop Recording' : 'Record',
              style: IconButton.styleFrom(
                backgroundColor: isRecording
                    ? Colors.red.shade700
                    : (isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFE2E8F0)),
                foregroundColor: isRecording ? Colors.white : Colors.red,
                padding: const EdgeInsets.all(12),
                side: BorderSide(
                  color: isRecording
                      ? Colors.red
                      : Colors.red.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              icon: Icon(
                isRecording ? Icons.stop : Icons.fiber_manual_record,
                size: 22,
              ),
              onPressed: isPlaying
                  ? null
                  : (isRecording ? onStopRecording : onStartRecording),
            ),
            const SizedBox(width: 12),

            // 2. Play / Stop Playback Button (Icon Only with Tooltip)
            IconButton.filledTonal(
              tooltip: isPlaying ? 'Stop Playback' : 'Play',
              style: IconButton.styleFrom(
                backgroundColor: isPlaying
                    ? Colors.orange.shade700
                    : (isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFE2E8F0)),
                foregroundColor: isPlaying
                    ? Colors.white
                    : (hasRecording ? accentColor : theme.disabledColor),
                padding: const EdgeInsets.all(12),
                side: BorderSide(
                  color: isPlaying
                      ? Colors.orange
                      : (hasRecording
                            ? accentColor.withValues(alpha: 0.4)
                            : Colors.grey.withValues(alpha: 0.2)),
                  width: 1.5,
                ),
              ),
              icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow, size: 24),
              onPressed: isRecording
                  ? null
                  : (isPlaying
                        ? onStopPlayback
                        : (hasRecording ? onStartPlayback : null)),
            ),
            const SizedBox(width: 12),

            // 3. Save Recording Button (Icon Only with Tooltip)
            IconButton.filledTonal(
              tooltip: 'Save Recording',
              style: IconButton.styleFrom(
                backgroundColor: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0),
                foregroundColor: (hasRecording && !isRecording && !isPlaying)
                    ? (isDark
                          ? const Color(0xFFFFD54F)
                          : const Color(0xFFF57F17))
                    : theme.disabledColor,
                padding: const EdgeInsets.all(12),
                side: BorderSide(
                  color: (hasRecording && !isRecording && !isPlaying)
                      ? const Color(0xFFFFD54F).withValues(alpha: 0.5)
                      : Colors.grey.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              icon: const Icon(Icons.save_outlined, size: 22),
              onPressed: (hasRecording && !isRecording && !isPlaying)
                  ? () => _showSaveDialog(context)
                  : null,
            ),
            const SizedBox(width: 12),

            // 4. Load Saved Recording Button (Icon Only with Tooltip)
            IconButton.filledTonal(
              tooltip: 'Load Saved Recording',
              style: IconButton.styleFrom(
                backgroundColor: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0),
                foregroundColor: (!isRecording && !isPlaying)
                    ? (isDark
                          ? const Color(0xFFB388FF)
                          : const Color(0xFF673AB7))
                    : theme.disabledColor,
                padding: const EdgeInsets.all(12),
                side: BorderSide(
                  color: (!isRecording && !isPlaying)
                      ? const Color(0xFFB388FF).withValues(alpha: 0.5)
                      : Colors.grey.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              icon: const Icon(Icons.folder_open, size: 22),
              onPressed: (!isRecording && !isPlaying)
                  ? () => _showLoadDialog(context)
                  : null,
            ),
          ],
        );
      },
    );
  }
}
