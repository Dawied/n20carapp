import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'bluetooth_manager.dart';
import 'widgets/virtual_joystick.dart';
import 'widgets/d_slider.dart';
import 'utils/file_downloader.dart';



final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(
  ThemeMode.dark,
);

void main() {
  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
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
  double _joystickX = 0.0;
  double _joystickY = 0.0;
  int _speed = 50;
  double _steeringStrength = 0.2;
  Timer? _heartbeatTimer;
  String _currentDirection = '';

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_currentDirection.isNotEmpty &&
          !_currentDirection.startsWith('joystick,0,0')) {
        _btManager.sendCommand(_currentDirection);
      }
    });
  }

  void _stopHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _handleJoystickInput(double x, double y) {
    final int intX = x.round();
    final int intY = y.round();

    setState(() {
      _joystickX = x;
      _joystickY = y;
    });

    final String command =
        'joystick,$intX,$intY,$_speed,${_steeringStrength.toStringAsFixed(1)}\n';
    if (command != _currentDirection) {
      _currentDirection = command;
      _btManager.sendCommand(command);
    }
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
  }

  @override
  void dispose() {
    _stopHeartbeatTimer();
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
                    onPressed: () {
                      themeModeNotifier.value = isDarkMode
                          ? ThemeMode.light
                          : ThemeMode.dark;
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
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
                      Icon(
                        isConnected
                            ? Icons.directions_car
                            : Icons.directions_car_outlined,
                        size: 70,
                        color: isConnected || isConnecting
                            ? accentColor
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isConnected
                            ? 'N20 Car Ready'
                            : (isConnecting
                                  ? 'Connecting to N20 Car...'
                                  : 'Connect to N20 Car'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 24),
                      VirtualJoystick(
                        onJoystickChanged: _handleJoystickInput,
                        onJoystickStop: _handleJoystickStop,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'X: ${_joystickX.toStringAsFixed(1)} | Y: ${_joystickY.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
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
                child: SpeedSlider(
                  currentSpeed: _speed,
                  minSpeed: 10,
                  maxSpeed: 255,
                  step: 5,
                  onSpeedChanged: (newSpeed) {
                    setState(() {
                      _speed = newSpeed;
                    });
                  },
                ),
              ),
              Positioned(
                right: 40,
                bottom: 40,
                child: SteeringStrengthSlider(
                  currentSteering: _steeringStrength,
                  minSteering: 0.1,
                  maxSteering: 1.0,
                  step: 0.1,
                  onSteeringChanged: (newSteering) {
                    setState(() {
                      _steeringStrength = newSteering;
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
