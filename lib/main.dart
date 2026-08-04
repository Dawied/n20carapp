import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'utils/bluetooth_manager.dart';
import 'widgets/virtual_joystick.dart';
import 'widgets/d_slider.dart';
import 'widgets/custom_snackbar.dart';
import 'widgets/recording.dart';
import 'utils/file_downloader.dart';



final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(
  ThemeMode.dark,
);


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);

  try {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool('is_dark_mode') ?? true;
    themeModeNotifier.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;
  } catch (_) {}

  runApp(const MyApp());
}


class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.on;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      try {
        _adapterStateSubscription = FlutterBluePlus.adapterState.listen((
          state,
        ) {
          _adapterState = state;
          if (mounted) {
            setState(() {});
          }
        }, onError: (_) {});
      } catch (_) {
        _adapterState = BluetoothAdapterState.on;
      }
    } else {
      _adapterState = BluetoothAdapterState.on;
    }
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget screen = (_adapterState == BluetoothAdapterState.on || kIsWeb)
        ? const MyHomePage(title: 'N20 Car Controller')
        : BluetoothOffScreen(adapterState: _adapterState);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'N20 Car App',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00BCD4),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFFFFFFF),
              foregroundColor: Color(0xFF0F172A),
              elevation: 1,
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Colors.white,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00E5FF),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF0B0F19),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF111827),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            cardTheme: CardThemeData(
              color: const Color(0xFF111827),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Color(0xFF111827),
            ),
          ),
          home: screen,
          navigatorObservers: [BluetoothAdapterStateObserver()],
        );
      },
    );
  }
}

class BluetoothAdapterStateObserver extends NavigatorObserver {
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name == '/DeviceScreen') {
      _adapterStateSubscription ??= FlutterBluePlus.adapterState.listen((
        state,
      ) {
        if (state != BluetoothAdapterState.on) {
          navigator?.pop();
        }
      });
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;
  }
}

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({super.key, this.adapterState});

  final BluetoothAdapterState? adapterState;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final subtextColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.bluetooth_disabled,
              size: 150.0,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
            const SizedBox(height: 16),
            Text(
              'Bluetooth Adapter is ${adapterState?.toString().split(".").last ?? "off"}.',
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please turn on Bluetooth to connect to your N20 Car.',
              style: TextStyle(color: subtextColor, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final BluetoothManager _btManager = BluetoothManager();
  final JoystickRecorder _recorder = JoystickRecorder();
  double _joystickX = 0.0;
  double _joystickY = 0.0;
  int _speed = 50;
  double _steeringStrength = 0.2;
  bool _swapSliders = false;
  bool _showRecordingControls = true;
  Timer? _heartbeatTimer;

  String _currentDirection = '';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _swapSliders = prefs.getBool('swap_sliders') ?? false;
          _showRecordingControls =
              prefs.getBool('show_recording_controls') ?? true;
        });
      }
    } catch (_) {}
  }


  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_currentDirection.isNotEmpty &&
          !_currentDirection.startsWith('joystick,0,0')) {
        _btManager.sendCommand(_currentDirection);
        if (_recorder.isRecording) {
          _recorder.recordCommand(
            _joystickX.round(),
            _joystickY.round(),
            _speed,
            _steeringStrength,
          );
        }
      }
    });
  }

  void _stopHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendCurrentJoystickCommand() {
    final int intX = _joystickX.round();
    final int intY = _joystickY.round();
    final String command =
        'joystick,$intX,$intY,$_speed,${_steeringStrength.toStringAsFixed(1)}\n';
    if (command != _currentDirection) {
      _currentDirection = command;
      _btManager.sendCommand(command);
      if (_recorder.isRecording) {
        _recorder.recordCommand(
          intX,
          intY,
          _speed,
          _steeringStrength,
        );
      }
    }
  }

  void _handleJoystickInput(double x, double y) {
    setState(() {
      _joystickX = x;
      _joystickY = y;
    });

    _sendCurrentJoystickCommand();

    if (_heartbeatTimer == null || !_heartbeatTimer!.isActive) {
      _startHeartbeatTimer();
    }
  }

  void _handleJoystickStop() {
    _stopHeartbeatTimer();
    setState(() {
      _joystickX = 0.0;
      _joystickY = 0.0;
    });
    final String command =
        'joystick,0,0,$_speed,${_steeringStrength.toStringAsFixed(1)}\n';
    _currentDirection = command;
    _btManager.sendCommand(command);
    if (_recorder.isRecording) {
      _recorder.recordCommand(0, 0, _speed, _steeringStrength);
    }
  }


  @override
  void dispose() {
    _stopHeartbeatTimer();
    _recorder.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark
        ? const Color(0xFF00E5FF)
        : const Color(0xFF00838F);

    return AnimatedBuilder(
      animation: _btManager,
      builder: (context, _) {
        final isConnected = _btManager.connectedDevice != null;
        final isConnecting = _btManager.isConnecting || _btManager.isScanning;

        final speedWidget = SpeedSlider(
          currentSpeed: _speed,
          minSpeed: 10,
          maxSpeed: 255,
          step: 5,
          onSpeedChanged: (newSpeed) {
            setState(() {
              _speed = newSpeed;
            });
            if (_joystickX != 0.0 || _joystickY != 0.0) {
              _sendCurrentJoystickCommand();
            }
          },
        );

        final steeringWidget = SteeringStrengthSlider(
          currentSteering: _steeringStrength,
          minSteering: 0.1,
          maxSteering: 1.0,
          step: 0.1,
          onSteeringChanged: (newSteering) {
            setState(() {
              _steeringStrength = newSteering;
            });
            if (_joystickX != 0.0 || _joystickY != 0.0) {
              _sendCurrentJoystickCommand();
            }
          },
        );

        return Scaffold(
          appBar: AppBar(
            leadingWidth: 140,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: isConnecting
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Connecting",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: accentColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : TextButton.icon(
                      icon: Icon(
                        Icons.bluetooth,
                        color: isConnected
                            ? accentColor
                            : theme.colorScheme.outline,
                        size: 20,
                      ),
                      label: Text(
                        isConnected ? "Disconnect" : "Connect",
                        style: TextStyle(
                          color: isConnected
                              ? accentColor
                              : theme.colorScheme.outline,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: isConnected
                          ? () => _btManager.disconnect()
                          : () => _btManager.startScan(),
                    ),
            ),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isConnected
                      ? 'Connected: ${_btManager.connectedDevice!.name}'
                      : (isConnecting ? 'Connecting...' : 'Disconnected'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isConnected || isConnecting
                        ? accentColor
                        : theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            actions: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeModeNotifier,
                builder: (context, mode, _) {
                  final isDarkMode = mode == ThemeMode.dark;
                  return IconButton(
                    tooltip: isDarkMode
                        ? 'Switch to Light Mode'
                        : 'Switch to Dark Mode',
                    icon: Icon(
                      isDarkMode ? Icons.light_mode : Icons.dark_mode,
                      color: isDarkMode
                          ? const Color(0xFFFFD54F)
                          : const Color(0xFF5C6BC0),
                    ),
                    onPressed: () async {
                      final newMode = isDarkMode
                          ? ThemeMode.light
                          : ThemeMode.dark;
                      themeModeNotifier.value = newMode;
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool(
                          'is_dark_mode',
                          newMode == ThemeMode.dark,
                        );
                      } catch (_) {}
                    },

                  );
                },
              ),
              IconButton(
                tooltip: 'Download Arduino code',
                icon: Icon(Icons.file_download_outlined, color: accentColor),
                onPressed: () async {
                  final message = await saveArduinoCodeToDownloads();
                  if (context.mounted) {
                    showAppSnackBar(context, message);
                  }

                },
              ),
              IconButton(
                tooltip: _showRecordingControls
                    ? 'Hide Recording Controls'
                    : 'Show Recording Controls',
                icon: Icon(
                  _showRecordingControls
                      ? Icons.videocam
                      : Icons.videocam_off_outlined,
                  color: _showRecordingControls
                      ? accentColor
                      : theme.colorScheme.outline,
                ),
                onPressed: () async {
                  setState(() {
                    _showRecordingControls = !_showRecordingControls;
                  });
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool(
                      'show_recording_controls',
                      _showRecordingControls,
                    );
                  } catch (_) {}
                },
              ),

              const SizedBox(width: 8),
            ],
            centerTitle: true,
          ),
          body: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      VirtualJoystick(
                        onJoystickChanged: _handleJoystickInput,
                        onJoystickStop: _handleJoystickStop,
                      ),
                      if (_showRecordingControls) ...[
                        const SizedBox(height: 16),
                        RecordingControlsWidget(
                          recorder: _recorder,
                          onStartRecording: () {
                            _recorder.startRecording();
                          },
                          onStopRecording: () {
                            _recorder.stopRecording();
                          },
                          onStartPlayback: () {
                            _stopHeartbeatTimer();
                            _recorder.playback(
                              onSendCommand: (command) async {
                                _currentDirection = command;
                                await _btManager.sendCommand(command);
                              },
                              onUpdatePosition: (x, y) {
                                setState(() {
                                  _joystickX = x;
                                  _joystickY = y;
                                });
                              },
                            );
                          },
                          onStopPlayback: () {
                            _recorder.stopPlayback();
                            _handleJoystickStop();
                          },
                        ),
                      ],
                      const SizedBox(height: 16),


                      if (_btManager.errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Card(
                            color: theme.colorScheme.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _btManager.errorMessage!,
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 40,
                bottom: 40,
                child: _swapSliders ? steeringWidget : speedWidget,
              ),
              Positioned(
                right: 40,
                bottom: 40,
                child: _swapSliders ? speedWidget : steeringWidget,
              ),
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? theme.colorScheme.surfaceContainerHighest
                          : const Color(0xFFE2E8F0),
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: accentColor.withValues(
                            alpha: isDark ? 0.3 : 0.45,
                          ),
                          width: 1.5,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.swap_horiz, size: 20),
                    label: const Text(
                      'Swap',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () async {
                      final newSwap = !_swapSliders;
                      setState(() {
                        _swapSliders = newSwap;
                      });
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('swap_sliders', newSwap);
                      } catch (_) {}
                    },

                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
