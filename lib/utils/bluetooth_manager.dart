import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Model for Discovered Device
class DiscoveredDevice {
  final String id;
  final String name;
  final int rssi;
  final dynamic originalDevice;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.originalDevice,
  });
}

/// Chrome Web Bluetooth State Manager for N20 Car
class BluetoothManager extends ChangeNotifier {
  static final BluetoothManager _instance = BluetoothManager._internal();
  factory BluetoothManager() => _instance;

  BluetoothManager._internal();

  StreamSubscription? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  List<DiscoveredDevice> _devices = [];
  List<DiscoveredDevice> get devices => _devices;

  DiscoveredDevice? _connectedDevice;
  DiscoveredDevice? get connectedDevice => _connectedDevice;

  BluetoothCharacteristic? _writeCharacteristic;
  String? _pendingCommand;
  bool _isSending = false;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final List<String> _consoleLogs = ["Chrome Bluetooth Manager initialized."];
  List<String> get consoleLogs => _consoleLogs;

  void addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _consoleLogs.insert(0, "[$timestamp] $message");
    if (_consoleLogs.length > 50) _consoleLogs.removeLast();
    notifyListeners();
  }

  /// Triggers Chrome's native Web Bluetooth selection picker
  Future<void> startScan() async {
    _devices.clear();
    _errorMessage = null;
    _isScanning = true;
    notifyListeners();
    addLog("Opening Chrome Web Bluetooth selection picker...");

    try {
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          final validResults = results
              .where(
                (r) =>
                    r.device.platformName.isNotEmpty ||
                    r.device.remoteId.str.isNotEmpty,
              )
              .toList();

          if (validResults.isNotEmpty) {
            _devices = validResults.map((r) {
              final name = r.device.platformName.isNotEmpty
                  ? r.device.platformName
                  : r.device.remoteId.str;
              return DiscoveredDevice(
                id: r.device.remoteId.str,
                name: name,
                rssi: r.rssi,
                originalDevice: r.device,
              );
            }).toList();

            notifyListeners();

            if (_connectedDevice == null && !_isConnecting) {
              addLog("Device selected in Chrome. Connecting immediately...");
              FlutterBluePlus.stopScan();
              connect(_devices.first);
            }
          }
        },
        onError: (e) {
          _errorMessage = "Scan error: $e";
          _isScanning = false;
          addLog("Error: $_errorMessage");
          notifyListeners();
        },
      );

      List<Guid> scanServices = [
        Guid("0000ffe0-0000-1000-8000-00805f9b34fb"), // HM-10 / AT-09 / MLT-BT05 / N20 Car
        Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e"), // Nordic UART
        Guid("0000fff0-0000-1000-8000-00805f9b34fb"), // JDY Serial
        Guid("0000ffe1-0000-1000-8000-00805f9b34fb"),
        Guid("00001101-0000-1000-8000-00805f9b34fb"),
      ];

      await FlutterBluePlus.startScan(
        withServices: scanServices,
        timeout: const Duration(seconds: 15),
      );

      _isScanning = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = "Scan failed: $e";
      _isScanning = false;
      addLog("Error: $_errorMessage");
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  Future<void> _cleanupConnection({bool cancelSubscription = true}) async {
    _connectedDevice = null;
    _writeCharacteristic = null;
    _pendingCommand = null;

    if (cancelSubscription) {
      await _connectionSubscription?.cancel();
    }
    _connectionSubscription = null;
  }

  /// Establishes GATT connection and discovers the write characteristic
  Future<void> connect(DiscoveredDevice device) async {
    _isConnecting = true;
    _errorMessage = null;
    await _connectionSubscription?.cancel();
    notifyListeners();
    addLog("Connecting to Chrome Web Bluetooth device: ${device.name}...");

    try {
      final bluetoothDevice = device.originalDevice as BluetoothDevice;

      _connectionSubscription = bluetoothDevice.connectionState.listen(
        (state) async {
          if (state == BluetoothConnectionState.disconnected) {
            if (_connectedDevice?.id == device.id) {
              addLog("Disconnected from ${device.name}.");
              await _cleanupConnection(cancelSubscription: false);
              notifyListeners();
            }
          }
        },
        onError: (e) {
          addLog("Connection state error: $e");
        },
      );

      await bluetoothDevice.connect(
        timeout: const Duration(seconds: 10),
      );
      addLog("GATT connection established with ${device.name}.");

      List<BluetoothService> services = await bluetoothDevice.discoverServices();
      addLog("GATT services discovered.");

      _writeCharacteristic = null;
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            String uuid = characteristic.uuid.str.toLowerCase();
            if (uuid.contains("ffe1") || uuid.contains("6e400002")) {
              _writeCharacteristic = characteristic;
              break;
            } else {
              _writeCharacteristic ??= characteristic;
            }
          }
        }
        if (_writeCharacteristic != null &&
            (_writeCharacteristic!.uuid.str.toLowerCase().contains("ffe1") ||
                _writeCharacteristic!.uuid.str.toLowerCase().contains("6e400002"))) {
          break;
        }
      }

      if (_writeCharacteristic != null) {
        _connectedDevice = device;
        addLog("Write characteristic ready. N20 Car connected.");

        // Immediately flush any command sent while connection/discovery was completing
        if (_pendingCommand != null) {
          final cmdToSend = _pendingCommand!;
          _pendingCommand = null;
          addLog("Flushing buffered initial command: '${cmdToSend.trim()}'");
          await sendCommand(cmdToSend);
        }
      } else {
        addLog("Warning: No writable characteristic found.");
      }
    } catch (e) {
      _errorMessage = "Connection failed: $e";
      addLog("Error: $_errorMessage");
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice == null) return;
    final name = _connectedDevice!.name;
    addLog("Disconnecting from $name...");

    try {
      final bluetoothDevice = _connectedDevice!.originalDevice as BluetoothDevice;
      await bluetoothDevice.disconnect();
    } catch (e) {
      addLog("Disconnect error: $e");
    } finally {
      await _cleanupConnection();
      notifyListeners();
    }
  }

  /// Sends command over BLE write characteristic using Last-In-Wins single-slot buffering
  Future<void> sendCommand(String command) async {
    // Always overwrite pending command with the latest input (Last-In-Wins)
    _pendingCommand = command;

    if (_connectedDevice == null || _writeCharacteristic == null) {
      return;
    }

    // If an in-flight BLE write is already running, return immediately.
    // The active transmit loop will pick up _pendingCommand automatically!
    if (_isSending) {
      return;
    }

    _isSending = true;

    try {
      while (_pendingCommand != null && _connectedDevice != null && _writeCharacteristic != null) {
        final cmdToSend = _pendingCommand!;
        _pendingCommand = null; // Clear before write so new updates set a fresh _pendingCommand

        addLog("Sent Command: '${cmdToSend.trim()}'");

        await _writeCharacteristic!.write(
          cmdToSend.codeUnits,
          withoutResponse: _writeCharacteristic!.properties.writeWithoutResponse,
        );

        // Small 30ms gap to avoid choking Chrome GATT hardware queue
        await Future.delayed(const Duration(milliseconds: 30));
      }
    } catch (e) {
      addLog("BLE write failed: $e");
      await disconnect();
    } finally {
      _isSending = false;
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }
}
