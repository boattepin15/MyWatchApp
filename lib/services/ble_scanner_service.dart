import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleScannerService {
  static final BleScannerService _instance = BleScannerService._internal();
  factory BleScannerService() => _instance;
  BleScannerService._internal();

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  // Request necessary permissions for BLE
  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  // Check if Bluetooth is on
  Future<bool> isBluetoothOn() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    return adapterState == BluetoothAdapterState.on;
  }

  // Start scanning for BLE devices
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    if (_isScanning) return;

    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      throw Exception('Bluetooth permissions not granted');
    }

    final btOn = await isBluetoothOn();
    if (!btOn) {
      throw Exception('Bluetooth is turned off');
    }

    _isScanning = true;
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
    );
    _isScanning = false;
  }

  // Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
  }

  // Get scan results stream
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  // Get scanning state stream
  Stream<bool> get isScanningStream => FlutterBluePlus.isScanning;

  // Connect to a device (simple, no retry)
  Future<void> connectToDevice(BluetoothDevice device) async {
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
  }

  /// Connect with auto-retry + clearGattCache for GATT error 133
  /// Returns a callback that reports status for UI display
  Future<void> connectWithRetry(
    BluetoothDevice device, {
    int maxAttempts = 3,
    void Function(String status)? onStatus,
  }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        onStatus?.call('Connecting... (attempt $attempt/$maxAttempts)');
        await device.connect(
          autoConnect: false,
          timeout: const Duration(seconds: 15),
        );
        onStatus?.call('Connected!');
        return; // Success!
      } catch (e) {
        final isGatt133 = e.toString().contains('133') ||
            e.toString().contains('ANDROID_SPECIFIC_ERROR');

        if (attempt < maxAttempts) {
          // Disconnect and clear cache before retrying
          try {
            onStatus?.call('Error${isGatt133 ? ' (GATT 133)' : ''} — clearing cache...');
            await device.disconnect();
            await Future.delayed(const Duration(milliseconds: 500));

            // Clear GATT cache (Android only, fixes error 133)
            if (isGatt133) {
              await device.clearGattCache();
              onStatus?.call('GATT cache cleared. Waiting before retry...');
            }

            // Delay before retry (increases with each attempt)
            final delay = Duration(seconds: 1 + attempt);
            await Future.delayed(delay);
          } catch (_) {
            // Ignore cleanup errors
            await Future.delayed(const Duration(seconds: 2));
          }
        } else {
          // Last attempt failed
          rethrow;
        }
      }
    }
  }

  // Disconnect from a device
  Future<void> disconnectFromDevice(BluetoothDevice device) async {
    await device.disconnect();
  }

  // Discover services of a connected device
  Future<List<BluetoothService>> discoverServices(BluetoothDevice device) async {
    return await device.discoverServices();
  }

  // Get heart rate data from Heart Rate Service (UUID: 0x180D)
  Stream<List<int>>? getHeartRateStream(List<BluetoothService> services) {
    for (var service in services) {
      if (service.uuid.toString().toUpperCase().contains('180D')) {
        for (var char in service.characteristics) {
          // Heart Rate Measurement characteristic (UUID: 0x2A37)
          if (char.uuid.toString().toUpperCase().contains('2A37')) {
            char.setNotifyValue(true);
            return char.onValueReceived;
          }
        }
      }
    }
    return null;
  }

  // Parse heart rate value from raw data
  static int parseHeartRate(List<int> data) {
    if (data.isEmpty) return 0;
    // Check if HR value is in 8-bit or 16-bit format
    final flags = data[0];
    if (flags & 0x01 == 0) {
      // 8-bit HR value
      return data.length > 1 ? data[1] : 0;
    } else {
      // 16-bit HR value
      return data.length > 2 ? (data[2] << 8) + data[1] : 0;
    }
  }
}
