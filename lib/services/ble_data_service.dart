import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Health data model containing steps, calories, distance, and heart rate
class HealthData {
  final int steps;
  final double calories;
  final double distanceKm;
  final int heartRate;
  final int goal;
  final int bloodOxygen;
  final double temperature;
  final int systolic;
  final int diastolic;
  final double hrv; // Heart Rate Variability (ms)
  final String movementLevel; // "Low", "Medium", "High"

  HealthData({
    this.steps = 0,
    this.calories = 0.0,
    this.distanceKm = 0.0,
    this.heartRate = 0,
    this.goal = 10000,
    this.bloodOxygen = 0,
    this.temperature = 0.0,
    this.systolic = 0,
    this.diastolic = 0,
    this.hrv = 0.0,
    this.movementLevel = 'Low',
  });

  HealthData copyWith({
    int? steps,
    double? calories,
    double? distanceKm,
    int? heartRate,
    int? goal,
    int? bloodOxygen,
    double? temperature,
    int? systolic,
    int? diastolic,
    double? hrv,
    String? movementLevel,
  }) {
    return HealthData(
      steps: steps ?? this.steps,
      calories: calories ?? this.calories,
      distanceKm: distanceKm ?? this.distanceKm,
      heartRate: heartRate ?? this.heartRate,
      goal: goal ?? this.goal,
      bloodOxygen: bloodOxygen ?? this.bloodOxygen,
      temperature: temperature ?? this.temperature,
      systolic: systolic ?? this.systolic,
      diastolic: diastolic ?? this.diastolic,
      hrv: hrv ?? this.hrv,
      movementLevel: movementLevel ?? this.movementLevel,
    );
  }
}

/// Device information model
class DeviceInfoData {
  final String modelNumber;
  final String firmwareRevision;
  final String hardwareRevision;
  final String manufacturer;

  DeviceInfoData({
    this.modelNumber = '--',
    this.firmwareRevision = '--',
    this.hardwareRevision = '--',
    this.manufacturer = '--',
  });
}

/// Characteristic value with metadata
class CharacteristicValue {
  final String serviceUuid;
  final String characteristicUuid;
  final List<int> rawValue;
  final String hexValue;
  final String stringValue;
  final DateTime timestamp;

  CharacteristicValue({
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.rawValue,
    required this.hexValue,
    required this.stringValue,
    required this.timestamp,
  });
}

/// HryFine Protocol Constants — Reverse-engineered from HryFine APK v3.7.32
class HryProtocol {
  // ──────── Primary: Nordic UART Service (NUS) ────────
  static const String nusServiceUuid =
      '6E400001-B5A3-F393-E0A9-E50E24DCCA9F';
  static const String nusWriteCharUuid =
      '6E400002-B5A3-F393-E0A9-E50E24DCCA9F';
  static const String nusNotifyCharUuid =
      '6E400003-B5A3-F393-E0A9-E50E24DCCA9F';

  // ──────── Fallback custom services (TWC watch) ────────
  // Ordered by most likely to work
  static const List<Map<String, String>> fallbackServices = [
    {'service': 'FF00', 'write': 'FF02', 'notify': 'FF01'},
    {'service': '0001', 'write': '0002', 'notify': '0003'},
    {'service': 'FF12', 'write': 'FF13', 'notify': 'FF14'},
    {'service': 'FF10', 'write': 'FFF1', 'notify': ''},  // write-only
  ];

  // ──────── Packet structure ────────
  static const int header = 0xDF;
  static const int ackResponseHeader = 0xFD;
  static const int protocolVersion = 1;

  // ──────── Command IDs ────────
  static const int cmdOta = 1;
  static const int cmdSettingOrder = 2;
  static const int cmdBandleDevice = 3;
  static const int cmdUnbandleDevice = 4;
  static const int cmdSportInfo = 5;
  static const int cmdResetDevice = 6;
  static const int cmdFactoryTest = 7;
  static const int cmdAlarmClock = 8;
  static const int cmdDeviceSetting = 9;
  static const int cmdFlashRead = 10;
  static const int cmdDeviceTest = 11;
  static const int cmdDeviceControl = 12;
  static const int cmdRestoreFactory = 13;
  static const int cmdWatchFace = 15;
  static const int cmdMedicationReminder = 16;
  static const int cmdDrinkReminder = 17;
  static const int cmdNewMessageRemind = 18;
  static const int cmdOtaNew = 19;
  static const int cmdSedentaryRemind = 20;
  static const int cmdGetFeature = 25;
  static const int cmdDeviceInfo = 0xF3; // -13 as unsigned byte
  static const int cmdFirmwareQuery = 0xF0; // -16 as unsigned byte

  // ──────── Sport sub-commands ────────
  static const int sportSyncAll = 1;
  static const int sportSyncStep = 2;
  static const int sportSyncSleep = 3;
  static const int sportSyncHeart = 4;
  static const int sportSyncBlood = 5;
  static const int sportRealTimeSwitch = 6;
  static const int sportHistoryStart = 7;
  static const int sportHistoryEnd = 8;
  static const int sportSyncSleepResult = 9;
  static const int sportSyncToday = 10;
  static const int sportSyncRealTimeStep = 12;

  // ──────── Setting sub-commands (CMD:2) ────────
  static const int settingSysTime = 1;
  static const int settingSwitchHeart = 13;
  static const int settingSwitchBloodPressure = 14;
  static const int settingSwitchTemperature = 25;
  static const int settingSwitchBloodOxygen = 28;

  // ──────── Response data types (byte[6] in response) ────────
  static const int dataStepsHourly = 2;
  static const int dataHeartRate = 4;
  static const int dataBloodPressure = 5;
  static const int dataHistoryStart = 7;
  static const int dataHistoryEnd = 8;
  static const int dataSleep = 9;
  static const int dataTotalSteps = 12;
  static const int dataTemperature = 13;
  static const int dataBloodOxygen = 14;
  static const int dataSportMode = 15;
  static const int dataWorkout = 16;

  // ──────── Measurement switch commands ────────
  /// Start/stop heart rate measurement on watch
  static List<int> switchHeartRate(bool on) =>
      buildPacket(cmdSettingOrder, settingSwitchHeart, [on ? 1 : 0]);

  /// Start/stop blood pressure measurement on watch
  static List<int> switchBloodPressure(bool on) =>
      buildPacket(cmdSettingOrder, settingSwitchBloodPressure, [on ? 1 : 0]);

  /// Start/stop temperature measurement on watch
  static List<int> switchTemperature(bool on) =>
      buildPacket(cmdSettingOrder, settingSwitchTemperature, [on ? 1 : 0]);

  /// Start/stop blood oxygen (SpO2) measurement on watch
  static List<int> switchBloodOxygen(bool on) =>
      buildPacket(cmdSettingOrder, settingSwitchBloodOxygen, [on ? 1 : 0]);

  /// Build a protocol packet: [0xDF, len_hi, len_lo, cmd_id, version, sub_cmd, data_len_hi, data_len_lo, ...data]
  /// Then insert checksum at byte[3].
  static List<int> buildPacket(int cmdId, int subCmd, [List<int>? data]) {
    final payload = data ?? [];
    // Without checksum: [header, len_hi, len_lo, cmdId, version, subCmd, dataLen_hi, dataLen_lo, ...payload]
    final packetLen = payload.length + 5; // cmdId + version + subCmd + 2 dataLen bytes
    final raw = <int>[
      header,
      (packetLen >> 8) & 0xFF,
      packetLen & 0xFF,
      cmdId & 0xFF,
      protocolVersion,
      subCmd & 0xFF,
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
      ...payload,
    ];
    // Calculate checksum (sum of all bytes), then insert at index 3
    return _addChecksum(raw);
  }

  /// Add checksum: sum all bytes → byte[3] = sum & 0xFF, shift rest right.
  static List<int> _addChecksum(List<int> raw) {
    int sum = 0;
    for (var b in raw) {
      sum += b;
    }
    final result = List<int>.filled(raw.length + 1, 0);
    // Copy first 3 bytes (header, len_hi, len_lo)
    result[0] = raw[0];
    result[1] = raw[1];
    result[2] = raw[2];
    // Insert checksum
    result[3] = sum & 0xFF;
    // Copy rest (cmdId, version, subCmd, dataLen, data...)
    for (int i = 3; i < raw.length; i++) {
      result[i + 1] = raw[i];
    }
    return result;
  }

  // ──────── Pre-built commands ────────
  static List<int> syncAllHistory() => buildPacket(cmdSportInfo, sportSyncAll);
  static List<int> syncTodayHistory() => buildPacket(cmdSportInfo, sportSyncToday);
  static List<int> enableRealTimeSteps() => buildPacket(cmdSportInfo, sportRealTimeSwitch, [1]);
  static List<int> disableRealTimeSteps() => buildPacket(cmdSportInfo, sportRealTimeSwitch, [0]);
  static List<int> requestDeviceInfo() => buildPacket(cmdDeviceInfo, 0);
  static List<int> requestSettings() => buildPacket(cmdDeviceSetting, 0);
  static List<int> requestAlarmClock() => buildPacket(cmdAlarmClock, 0);
  static List<int> unbindDevice() => buildPacket(cmdUnbandleDevice, 0);
  static List<int> restoreFactory() => buildPacket(cmdRestoreFactory, 0);
  static List<int> requestFeatures() => buildPacket(cmdGetFeature, 0);
  static List<int> bindDevice(String userId) {
    final userBytes = utf8.encode(userId.length > 8 ? userId.substring(0, 8) : userId);
    return buildPacket(cmdBandleDevice, 0, userBytes);
  }

  /// Parse 2-byte big-endian int
  static int byte2Int(int hi, int lo) => ((hi & 0xFF) << 8) | (lo & 0xFF);

  /// Parse 4-byte big-endian int
  static int byte4Int(int b0, int b1, int b2, int b3) =>
      ((b0 & 0xFF) << 24) | ((b1 & 0xFF) << 16) | ((b2 & 0xFF) << 8) | (b3 & 0xFF);
}


class BleDataService {
  static final BleDataService _instance = BleDataService._internal();
  factory BleDataService() => _instance;
  BleDataService._internal();

  // Standard BLE service UUIDs
  static const String batteryServiceUuid = '180f';
  static const String deviceInfoServiceUuid = '180a';
  static const String heartRateServiceUuid = '180d';

  // Standard BLE characteristic UUIDs
  static const String batteryLevelCharUuid = '2a19';
  static const String heartRateMeasurementCharUuid = '2a37';
  static const String modelNumberCharUuid = '2a24';
  static const String firmwareRevisionCharUuid = '2a26';
  static const String hardwareRevisionCharUuid = '2a27';
  static const String manufacturerNameCharUuid = '2a29';

  // Known custom service UUIDs for TWC-like watches
  static const List<String> customServiceUuids = [
    'ff10', 'ff12', '0001', 'ff00',
  ];

  // Stream controllers
  final _healthDataController = StreamController<HealthData>.broadcast();
  final _batteryController = StreamController<int>.broadcast();
  final _deviceInfoController = StreamController<DeviceInfoData>.broadcast();
  final _characteristicValueController =
      StreamController<CharacteristicValue>.broadcast();
  final _protocolLogController = StreamController<String>.broadcast();

  Stream<HealthData> get healthDataStream => _healthDataController.stream;
  Stream<int> get batteryStream => _batteryController.stream;
  Stream<DeviceInfoData> get deviceInfoStream => _deviceInfoController.stream;
  Stream<CharacteristicValue> get characteristicValueStream =>
      _characteristicValueController.stream;
  Stream<String> get protocolLogStream => _protocolLogController.stream;

  // Active subscriptions
  final List<StreamSubscription> _subscriptions = [];

  // Current health data
  HealthData _currentHealth = HealthData();
  HealthData get currentHealth => _currentHealth;

  int _batteryLevel = -1;
  int get batteryLevel => _batteryLevel;

  DeviceInfoData _deviceInfo = DeviceInfoData();
  DeviceInfoData get deviceInfo => _deviceInfo;

  // HryFine protocol state
  BluetoothCharacteristic? _nusWriteChar;
  BluetoothCharacteristic? _nusNotifyChar;
  List<int>? _receiveBuffer;
  int _receivePos = 0;
  bool _isBound = false;
  bool get isBound => _isBound;
  String _firmwareVersion = '';
  String get firmwareVersion => _firmwareVersion;
  BluetoothDevice? _device;  // Store device reference for connection checks
  Timer? _autoSyncTimer;     // Auto-sync health data periodically

  // Movement level tracking
  int _previousSteps = 0;
  DateTime _previousStepTime = DateTime.now();

  // HRV calculation
  double _computeHrv(int hr) {
    if (hr <= 0) return 0.0;
    return 60000.0 / hr; // Approximate RR-interval in ms
  }

  // Movement level from step rate
  String _computeMovementLevel(int currentSteps) {
    final now = DateTime.now();
    final elapsed = now.difference(_previousStepTime).inSeconds;
    if (elapsed < 5) return _currentHealth.movementLevel; // Too soon, keep current

    final stepDiff = currentSteps - _previousSteps;
    final stepsPerMinute = elapsed > 0 ? (stepDiff / elapsed * 60).round() : 0;

    _previousSteps = currentSteps;
    _previousStepTime = now;

    if (stepsPerMinute >= 120) return 'High';
    if (stepsPerMinute >= 40) return 'Medium';
    return 'Low';
  }

  // ════════════════════════════════════════════════════════
  //  HryFine Protocol — Nordic UART Service
  // ════════════════════════════════════════════════════════

  /// Find and cache the best write/notify characteristic pair.
  /// Priority: NUS → FF00 → 0001 → FF12 → any writable+notify pair
  bool findNusService(List<BluetoothService> services) {
    // --- Attempt 1: Nordic UART Service ---
    for (var service in services) {
      final sUuid = service.uuid.toString().toUpperCase();
      if (sUuid.contains('6E400001')) {
        for (var char in service.characteristics) {
          final cUuid = char.uuid.toString().toUpperCase();
          if (cUuid.contains('6E400002')) {
            _nusWriteChar = char;
            _log('✓ Found NUS Write: $cUuid');
          } else if (cUuid.contains('6E400003')) {
            _nusNotifyChar = char;
            _log('✓ Found NUS Notify: $cUuid');
          }
        }
        if (_nusWriteChar != null && _nusNotifyChar != null) {
          _log('✓ Using Nordic UART Service');
          return true;
        }
      }
    }

    // --- Attempt 2: Known custom service fallbacks ---
    for (var fb in HryProtocol.fallbackServices) {
      final targetService = fb['service']!;
      final targetWrite = fb['write']!;
      final targetNotify = fb['notify']!;

      for (var service in services) {
        final sUuid = _shortUuid(service.uuid.toString());
        if (sUuid == targetService) {
          BluetoothCharacteristic? writeChar;
          BluetoothCharacteristic? notifyChar;

          for (var char in service.characteristics) {
            final cUuid = _shortUuid(char.uuid.toString());
            if (cUuid == targetWrite &&
                (char.properties.write || char.properties.writeWithoutResponse)) {
              writeChar = char;
            }
            if (targetNotify.isNotEmpty && cUuid == targetNotify &&
                (char.properties.notify || char.properties.indicate)) {
              notifyChar = char;
            }
          }

          if (writeChar != null) {
            _nusWriteChar = writeChar;
            _log('✓ Fallback Write: 0x$targetWrite (Service 0x$targetService)');
            if (notifyChar != null) {
              _nusNotifyChar = notifyChar;
              _log('✓ Fallback Notify: 0x$targetNotify (Service 0x$targetService)');
              return true;
            }
          }
        }
      }
    }

    // --- Attempt 3: Any service with write + notify pair ---
    for (var service in services) {
      final sUuid = _shortUuid(service.uuid.toString());
      // Skip standard services
      if (['180F', '180A', '1800', '1801'].contains(sUuid)) continue;

      BluetoothCharacteristic? writeChar;
      BluetoothCharacteristic? notifyChar;

      for (var char in service.characteristics) {
        if (char.properties.write || char.properties.writeWithoutResponse) {
          writeChar ??= char;
        }
        if (char.properties.notify || char.properties.indicate) {
          notifyChar ??= char;
        }
      }

      if (writeChar != null && notifyChar != null) {
        _nusWriteChar = writeChar;
        _nusNotifyChar = notifyChar;
        _log('✓ Auto-detected Write: ${_shortUuid(writeChar.uuid.toString())} '
            'Notify: ${_shortUuid(notifyChar.uuid.toString())} '
            '(Service 0x$sUuid)');
        return true;
      }
    }

    // --- Attempt 4: At least find a write characteristic ---
    for (var service in services) {
      final sUuid = _shortUuid(service.uuid.toString());
      if (['180F', '180A', '1800', '1801'].contains(sUuid)) continue;

      for (var char in service.characteristics) {
        if (char.properties.write || char.properties.writeWithoutResponse) {
          _nusWriteChar = char;
          _log('⚠ Only found Write: ${_shortUuid(char.uuid.toString())} '
              '(Service 0x$sUuid) — no notify char');
          return true;  // Can send commands but may not receive responses
        }
      }
    }

    _log('✗ No suitable write characteristic found!');
    return false;
  }

  /// Subscribe to all available notification characteristics
  Future<void> subscribeAllNotify(List<BluetoothService> services) async {
    for (var service in services) {
      final sUuid = _shortUuid(service.uuid.toString());
      if (['180F', '180A', '1800', '1801'].contains(sUuid)) continue;

      for (var char in service.characteristics) {
        if (char.properties.notify || char.properties.indicate) {
          try {
            await char.setNotifyValue(true);
            final sub = char.onValueReceived.listen((data) {
              _emitCharacteristicValue(char, data);
              _handleNusData(data);
            });
            _subscriptions.add(sub);
            _log('✓ Subscribed: 0x${_shortUuid(char.uuid.toString())} '
                '(Service 0x$sUuid)');
          } catch (e) {
            _log('✗ Subscribe 0x${_shortUuid(char.uuid.toString())} error: $e');
          }
        }
      }
    }
  }

  String _shortUuid(String uuid) {
    final upper = uuid.toUpperCase();
    return upper.length >= 8 ? upper.substring(4, 8) : upper;
  }

  /// Subscribe to NUS notifications and start receiving data
  Future<void> subscribeNus() async {
    if (_nusNotifyChar == null) {
      _log('✗ NUS Notify char not found');
      return;
    }
    try {
      await _nusNotifyChar!.setNotifyValue(true);
      final sub = _nusNotifyChar!.onValueReceived.listen((data) {
        _emitCharacteristicValue(_nusNotifyChar!, data);
        _handleNusData(data);
      });
      _subscriptions.add(sub);
      _log('✓ Subscribed to NUS notifications');
    } catch (e) {
      _log('✗ Subscribe NUS error: $e');
    }
  }

  /// Write a HryFine protocol command (with connection check)
  Future<bool> writeNusCommand(List<int> packet) async {
    if (_nusWriteChar == null) {
      _log('✗ NUS Write char not found');
      return false;
    }
    // Check if device is still connected
    if (_device != null && !_device!.isConnected) {
      _log('✗ Device disconnected, cannot write');
      return false;
    }
    try {
      // Split into 20-byte chunks (BLE MTU limit)
      var remaining = packet;
      while (remaining.length > 20) {
        final chunk = remaining.sublist(0, 20);
        await _nusWriteChar!.write(chunk, withoutResponse: true);
        remaining = remaining.sublist(20);
        await Future.delayed(const Duration(milliseconds: 20));
      }
      await _nusWriteChar!.write(remaining, withoutResponse: true);
      _log('→ Sent: ${bytesToHex(packet)}');
      return true;
    } catch (e) {
      _log('✗ Write error: $e');
      return false;
    }
  }

  /// Full HryFine connection flow: subscribe → bind → sync
  Future<void> startHryProtocol(List<BluetoothService> services,
      {String userId = 'FlutterU', BluetoothDevice? device}) async {
    _log('═══ Starting HryFine Protocol ═══');
    _device = device;

    // Step 0: Find write/notify characteristics
    final found = findNusService(services);
    if (!found) {
      _log('✗ No writable characteristic found!');
      await readBatteryLevel(services);
      await readDeviceInfo(services);
      return;
    }

    // Step 1: Subscribe ONLY to NUS notify (subscribing to other chars
    // causes the TWC watch to disconnect!)
    await subscribeNus();
    // Give the watch time to stabilize after subscribe
    await Future.delayed(const Duration(milliseconds: 1000));

    // Connection check before proceeding
    if (_device != null && !_device!.isConnected) {
      _log('✗ Device disconnected after subscribe! Aborting.');
      return;
    }

    // Step 2: Bind device first (establishes trust)
    _log('→ Binding device...');
    await writeNusCommand(HryProtocol.bindDevice(userId));
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 3: Request features
    _log('→ Requesting features...');
    await writeNusCommand(HryProtocol.requestFeatures());
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 4: Request settings
    _log('→ Requesting settings...');
    await writeNusCommand(HryProtocol.requestSettings());
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 5: Sync today's data
    _log('→ Syncing today\'s health data...');
    await writeNusCommand(HryProtocol.syncTodayHistory());
    await Future.delayed(const Duration(milliseconds: 300));

    // Step 6: Enable real-time steps
    _log('→ Enabling real-time steps...');
    await writeNusCommand(HryProtocol.enableRealTimeSteps());

    // Also read standard services
    await readBatteryLevel(services);
    await readDeviceInfo(services);

    _log('═══ Protocol init complete ═══');

    // Step 7: Start auto-sync timer
    startAutoSync();
  }

  /// Start periodic auto-sync (every 30 seconds)
  void startAutoSync({Duration interval = const Duration(seconds: 30)}) {
    stopAutoSync();
    _log('⏰ Auto-sync started (every ${interval.inSeconds}s)');
    _autoSyncTimer = Timer.periodic(interval, (_) => _autoSyncTick());
  }

  /// Stop auto-sync timer
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// Single auto-sync tick: start measurements + pull ALL health data
  Future<void> _autoSyncTick() async {
    if (_device != null && !_device!.isConnected) {
      _log('⚠ Auto-sync skipped — device disconnected');
      stopAutoSync();
      return;
    }

    _log('🔄 Auto-sync...');

    // 1. Start measurements on watch
    await writeNusCommand(HryProtocol.switchHeartRate(true));
    await Future.delayed(const Duration(milliseconds: 200));
    await writeNusCommand(HryProtocol.switchBloodOxygen(true));
    await Future.delayed(const Duration(milliseconds: 200));
    await writeNusCommand(HryProtocol.switchBloodPressure(true));
    await Future.delayed(const Duration(milliseconds: 200));
    await writeNusCommand(HryProtocol.switchTemperature(true));
    await Future.delayed(const Duration(milliseconds: 200));

    // 2. Enable real-time step switch (THIS triggers step data push)
    await writeNusCommand(HryProtocol.buildPacket(
      HryProtocol.cmdSportInfo, HryProtocol.sportRealTimeSwitch, [1]));
    await Future.delayed(const Duration(milliseconds: 500));

    // 3. Today's history (steps, HR, BP, sleep, temp, SpO2)
    await writeNusCommand(HryProtocol.syncTodayHistory());
    await Future.delayed(const Duration(milliseconds: 300));

    // 4. Sync all history data
    await writeNusCommand(HryProtocol.syncAllHistory());
  }

  /// Request full history sync
  Future<void> syncAllHistory() async {
    _log('→ Syncing all history...');
    await writeNusCommand(HryProtocol.syncAllHistory());
  }

  /// Request today's data
  Future<void> syncTodayData() async {
    _log('→ Syncing today\'s data...');
    await writeNusCommand(HryProtocol.syncTodayHistory());
  }

  // ════════════════════════════════════════════════════════
  //  HryFine Response Parser
  // ════════════════════════════════════════════════════════

  void _handleNusData(List<int> data) {
    if (data.isEmpty) return;

    if (_receiveBuffer == null) {
      // New packet
      if (data[0] == HryProtocol.header) {
        // Data packet starting with 0xDF
        final expectedLen = ((data[1] & 0xFF) << 8) + (data[2] & 0xFF) + 4; // +4 for header+len+checksum
        _receiveBuffer = List<int>.filled(expectedLen, 0);
        final copyLen = data.length < expectedLen ? data.length : expectedLen;
        for (int i = 0; i < copyLen; i++) {
          _receiveBuffer![i] = data[i];
        }
        _receivePos = data.length;
        _log('◀ [${data.length}/$expectedLen] ${bytesToHex(data.take(10).toList())}...');
      } else if (data[0] == HryProtocol.ackResponseHeader) {
        // ACK response
        _log('◀ ACK: ${bytesToHex(data)}');
        _handleAck(data);
        return;
      } else {
        _log('◀ Unknown: ${bytesToHex(data)}');
        return;
      }
    } else {
      // Continue receiving fragmented packet
      for (int i = 0; i < data.length && _receivePos < _receiveBuffer!.length; i++) {
        _receiveBuffer![_receivePos++] = data[i];
      }
    }

    // Check if packet is complete
    if (_receiveBuffer != null && _receivePos >= _receiveBuffer!.length) {
      final packet = List<int>.from(_receiveBuffer!);
      _receiveBuffer = null;
      _receivePos = 0;
      _processCompletePacket(packet);
    }
  }

  void _processCompletePacket(List<int> packet) {
    if (packet.length < 9) return;

    // Verify checksum (byte[3] = sum of all other bytes & 0xFF)
    int sum = 0;
    for (int i = 0; i < packet.length; i++) {
      if (i != 3) sum += packet[i];
    }
    if ((sum & 0xFF) != (packet[3] & 0xFF)) {
      _log('⚠ Checksum mismatch');
    }

    final cmdId = packet[4] & 0xFF;
    final subCmd = packet[6] & 0xFF;
    _log('◀ CMD:0x${cmdId.toRadixString(16).toUpperCase()} SUB:$subCmd [${packet.length}B]');

    // Send ACK back to watch
    _sendAck(cmdId, subCmd);

    // Parse based on command ID
    if (cmdId == HryProtocol.cmdSportInfo) {
      _parseHealthData(packet);
    } else if (cmdId == HryProtocol.cmdDeviceControl) {
      _log('  Device control response');
    } else if (cmdId == HryProtocol.cmdDeviceSetting) {
      _log('  Settings received');
    } else if (cmdId == HryProtocol.cmdGetFeature) {
      _log('  Features received');
    } else if (cmdId == 0xF3 || cmdId == 0xF0) {
      _parseFirmwareInfo(packet);
    } else {
      _log('  Unhandled CMD:0x${cmdId.toRadixString(16)}');
    }
  }

  void _parseHealthData(List<int> packet) {
    if (packet.length < 10) return;

    // Data payload starts at byte[9]
    // bytes[7-8] = exact data payload length
    final dataLen = HryProtocol.byte2Int(packet[7], packet[8]);
    if (dataLen <= 0) return;

    final payload = packet.sublist(9, (9 + dataLen).clamp(0, packet.length));
    final dataType = packet[6] & 0xFF;

    switch (dataType) {
      case HryProtocol.dataStepsHourly:
        _log('  📊 Steps (hourly data) [${payload.length}B]');
        _log('     RAW: ${bytesToHex(payload.take(20).toList())}${payload.length > 20 ? "..." : ""}');
        break;

      case HryProtocol.dataHeartRate:
        _log('  ❤️ Heart Rate data [${payload.length}B]');
        _parseHeartRateHistory(payload);
        break;

      case HryProtocol.dataBloodPressure:
        _log('  🩸 Blood Pressure data [${payload.length}B]');
        _parseBloodPressure(payload);
        break;

      case HryProtocol.dataHistoryStart:
        _log('  ▶ History sync started');
        break;

      case HryProtocol.dataHistoryEnd:
        _log('  ■ History sync complete');
        // Re-enable real-time step updates after history sync
        _log('  → Re-enabling real-time steps...');
        writeNusCommand(HryProtocol.buildPacket(
          HryProtocol.cmdSportInfo, HryProtocol.sportRealTimeSwitch, [1]));
        break;

      case HryProtocol.dataSleep:
        _log('  😴 Sleep data [${payload.length}B]');
        _log('     RAW: ${bytesToHex(payload.take(20).toList())}${payload.length > 20 ? "..." : ""}');
        break;

      case HryProtocol.dataTotalSteps:
        _log('  🏃 Total steps today');
        _parseTotalSteps(payload);
        break;

      case HryProtocol.dataTemperature:
        _log('  🌡️ Temperature data [${payload.length}B]');
        _parseTemperature(payload);
        break;

      case HryProtocol.dataBloodOxygen:
        _log('  🫁 Blood Oxygen (SpO2) data');
        _parseBloodOxygen(payload);
        break;

      case HryProtocol.dataSportMode:
        _log('  🏋️ Sport mode data [${payload.length}B]');
        break;

      case HryProtocol.dataWorkout:
        _log('  ⏱️ Workout data');
        _parseWorkout(payload);
        break;

      default:
        _log('  Unknown data type: $dataType [${payload.length}B]');
        _log('     RAW: ${bytesToHex(payload.take(20).toList())}');
    }
  }

  void _parseTotalSteps(List<int> payload) {
    _log('     RAW: ${bytesToHex(payload)}');
    if (payload.length < 4) return;
    // TotalStepData from StepUtils.getTotalStepData:
    // [0..3] = steps, [4..7] = distance(m), [8..11] = calories
    try {
      int steps = 0;
      int distance = 0;
      int calories = 0;

      steps = HryProtocol.byte4Int(payload[0], payload[1], payload[2], payload[3]);
      if (payload.length >= 8) {
        distance = HryProtocol.byte4Int(payload[4], payload[5], payload[6], payload[7]);
      }
      if (payload.length >= 12) {
        calories = HryProtocol.byte4Int(payload[8], payload[9], payload[10], payload[11]);
      }

      final movLevel = _computeMovementLevel(steps);
      _log('     ✓ Steps: $steps, Dist: ${distance}m, Cal: $calories (raw), Movement: $movLevel');

      _currentHealth = _currentHealth.copyWith(
        steps: steps,
        calories: calories / 1000.0,  // raw value is in sub-units, ÷1000 for kcal
        distanceKm: distance / 1000.0,
        movementLevel: movLevel,
      );
      _healthDataController.add(_currentHealth);
    } catch (e) {
      _log('     Parse error: $e');
    }
  }

  void _parseHeartRateHistory(List<int> payload) {
    // HR data list from HrUtils.getHrDataList
    // Each record: [date_hi, date_lo, time(4B), hr_value, ...]
    try {
      if (payload.length >= 3) {
        // Get the last HR value as current
        int lastHr = 0;
        // Simple: scan for valid HR values (40-220 range)
        for (int i = payload.length - 1; i >= 0; i--) {
          final v = payload[i] & 0xFF;
          if (v >= 40 && v <= 220) {
            lastHr = v;
            break;
          }
        }
        if (lastHr > 0) {
          final computedHrv = _computeHrv(lastHr);
          _log('     Last HR: $lastHr BPM, HRV: ${computedHrv.toStringAsFixed(1)} ms');
          _currentHealth = _currentHealth.copyWith(
            heartRate: lastHr,
            hrv: computedHrv,
          );
          _healthDataController.add(_currentHealth);
        }
      }
      _log('     RAW: ${bytesToHex(payload.take(20).toList())}${payload.length > 20 ? "..." : ""}');
    } catch (e) {
      _log('     Parse error: $e');
    }
  }

  void _parseBloodPressure(List<int> payload) {
    try {
      // Blood pressure: systolic and diastolic values
      if (payload.length >= 8) {
        // Scan for values in typical BP range
        for (int i = 0; i < payload.length - 1; i++) {
          final v1 = payload[i] & 0xFF;
          final v2 = payload[i + 1] & 0xFF;
          if (v1 >= 80 && v1 <= 200 && v2 >= 40 && v2 <= 130) {
            _log('     BP: $v1/$v2 mmHg');
            _currentHealth = _currentHealth.copyWith(
              systolic: v1,
              diastolic: v2,
            );
            _healthDataController.add(_currentHealth);
            break;
          }
        }
      }
      _log('     RAW: ${bytesToHex(payload.take(20).toList())}');
    } catch (e) {
      _log('     Parse error: $e');
    }
  }

  void _parseTemperature(List<int> payload) {
    try {
      // Temperature data from TempUtils format
      if (payload.length >= 4) {
        // Scan payload for valid temp values (350-420 = 35.0-42.0°C)
        for (int i = 0; i < payload.length - 1; i++) {
          final temp16 = HryProtocol.byte2Int(payload[i], payload[i + 1]);
          if (temp16 >= 350 && temp16 <= 420) {
            final tempC = temp16 / 10.0;
            _log('     Temp: ${tempC}°C');
            _currentHealth = _currentHealth.copyWith(temperature: tempC);
            _healthDataController.add(_currentHealth);
            break;
          }
        }
      }
      _log('     RAW: ${bytesToHex(payload.take(20).toList())}');
    } catch (e) {
      _log('     Parse error: $e');
    }
  }

  void _parseBloodOxygen(List<int> payload) {
    try {
      // SpO2 value at payload[11] from the decompiled code
      if (payload.length >= 12) {
        final spo2 = payload[11] & 0xFF;
        if (spo2 >= 80 && spo2 <= 100) {
          _log('     SpO2: $spo2%');
          _currentHealth = _currentHealth.copyWith(bloodOxygen: spo2);
          _healthDataController.add(_currentHealth);
        }
      }
      _log('     RAW: ${bytesToHex(payload.take(20).toList())}');
    } catch (e) {
      _log('     Parse error: $e');
    }
  }

  void _parseWorkout(List<int> payload) {
    try {
      if (payload.length >= 29) {
        final duration = HryProtocol.byte4Int(payload[6], payload[7], payload[8], payload[9]);
        final mode = payload[10] & 0xFF;
        final calories = HryProtocol.byte4Int(payload[17], payload[18], payload[19], payload[20]);
        final distance = HryProtocol.byte4Int(payload[21], payload[22], payload[23], payload[24]);
        final steps = HryProtocol.byte4Int(payload[25], payload[26], payload[27], payload[28]);
        _log('     Workout: mode=$mode dur=${duration}s steps=$steps cal=$calories dist=${distance}m');
      }
      _log('     RAW: ${bytesToHex(payload.take(30).toList())}');
    } catch (e) {
      _log('     Parse error: $e');
    }
  }

  void _parseFirmwareInfo(List<int> packet) {
    try {
      if (packet.length > 14) {
        final vLen = packet[13] & 0xFF;
        if (packet.length > 14 + vLen) {
          _firmwareVersion = String.fromCharCodes(packet.sublist(14, 14 + vLen));
          _log('  Firmware: $_firmwareVersion');
        }
      }
    } catch (e) {
      _log('  Firmware parse error: $e');
    }
  }

  void _handleAck(List<int> data) {
    if (data.length < 9) return;
    final cmdId = data[4] & 0xFF;
    final subCmd = data[5] & 0xFF;
    final success = (data[8] & 0xFF) == 1;
    _log('  ACK for CMD:0x${cmdId.toRadixString(16)} SUB:$subCmd ${success ? "✓" : "✗"}');

    if (cmdId == HryProtocol.cmdBandleDevice && success) {
      _isBound = true;
      _log('  ✓ Device bound successfully');
    }
  }

  void _sendAck(int cmdId, int subCmd) {
    // ACK packet: simplified version
    // From AckPackageConfigUtils.configAck
    final ack = <int>[
      HryProtocol.ackResponseHeader,
      0x00, 0x06,               // length
      cmdId & 0xFF,
      subCmd & 0xFF,
      0x00, 0x00,               // sequence
      0x00,                     // error code
      0x01,                     // success
    ];
    writeNusCommand(ack);
  }

  void _log(String msg) {
    print('[BLE] $msg');
    _protocolLogController.add(msg);
  }

  // ════════════════════════════════════════════════════════
  //  Standard BLE Services (unchanged)
  // ════════════════════════════════════════════════════════

  /// Read battery level from Battery Service (0x180F)
  Future<int> readBatteryLevel(List<BluetoothService> services) async {
    try {
      for (var service in services) {
        if (_matchUuid(service.uuid, batteryServiceUuid)) {
          for (var char in service.characteristics) {
            if (_matchUuid(char.uuid, batteryLevelCharUuid)) {
              final value = await char.read();
              if (value.isNotEmpty) {
                _batteryLevel = value[0];
                _batteryController.add(_batteryLevel);
                return _batteryLevel;
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error reading battery: $e');
    }
    return -1;
  }

  /// Read device information from Device Information Service (0x180A)
  Future<DeviceInfoData> readDeviceInfo(
      List<BluetoothService> services) async {
    String model = '--';
    String firmware = '--';
    String hardware = '--';
    String manufacturer = '--';

    try {
      for (var service in services) {
        if (_matchUuid(service.uuid, deviceInfoServiceUuid)) {
          for (var char in service.characteristics) {
            try {
              if (_matchUuid(char.uuid, modelNumberCharUuid)) {
                final value = await char.read();
                model = _bytesToString(value);
              } else if (_matchUuid(char.uuid, firmwareRevisionCharUuid)) {
                final value = await char.read();
                firmware = _bytesToString(value);
              } else if (_matchUuid(char.uuid, hardwareRevisionCharUuid)) {
                final value = await char.read();
                hardware = _bytesToString(value);
              } else if (_matchUuid(char.uuid, manufacturerNameCharUuid)) {
                final value = await char.read();
                manufacturer = _bytesToString(value);
              }
            } catch (e) {
              print('Error reading device info char: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error reading device info: $e');
    }

    _deviceInfo = DeviceInfoData(
      modelNumber: model,
      firmwareRevision: firmware,
      hardwareRevision: hardware,
      manufacturer: manufacturer,
    );
    _deviceInfoController.add(_deviceInfo);
    return _deviceInfo;
  }

  /// Subscribe to heart rate notifications
  StreamSubscription? subscribeHeartRate(List<BluetoothService> services) {
    try {
      for (var service in services) {
        if (_matchUuid(service.uuid, heartRateServiceUuid)) {
          for (var char in service.characteristics) {
            if (_matchUuid(char.uuid, heartRateMeasurementCharUuid)) {
              char.setNotifyValue(true);
              final sub = char.onValueReceived.listen((data) {
                final hr = _parseStandardHeartRate(data);
                _currentHealth = _currentHealth.copyWith(heartRate: hr);
                _healthDataController.add(_currentHealth);
              });
              _subscriptions.add(sub);
              return sub;
            }
          }
        }
      }
    } catch (e) {
      print('Error subscribing to heart rate: $e');
    }
    return null;
  }

  /// Read a specific characteristic by UUID
  Future<List<int>> readCharacteristic(
      BluetoothCharacteristic characteristic) async {
    try {
      final value = await characteristic.read();
      _emitCharacteristicValue(characteristic, value);
      return value;
    } catch (e) {
      print('Error reading characteristic: $e');
      return [];
    }
  }

  /// Write data to a specific characteristic
  Future<void> writeCharacteristic(
      BluetoothCharacteristic characteristic, List<int> data,
      {bool withoutResponse = false}) async {
    try {
      await characteristic.write(data, withoutResponse: withoutResponse);
    } catch (e) {
      print('Error writing characteristic: $e');
    }
  }

  /// Subscribe to notifications on a specific characteristic
  StreamSubscription? subscribeCharacteristic(
      BluetoothCharacteristic characteristic) {
    try {
      characteristic.setNotifyValue(true);
      final sub = characteristic.onValueReceived.listen((data) {
        _emitCharacteristicValue(characteristic, data);
        _tryParseHealthData(characteristic, data);
      });
      _subscriptions.add(sub);
      return sub;
    } catch (e) {
      print('Error subscribing to characteristic: $e');
      return null;
    }
  }

  /// Unsubscribe from notifications on a specific characteristic
  Future<void> unsubscribeCharacteristic(
      BluetoothCharacteristic characteristic) async {
    try {
      await characteristic.setNotifyValue(false);
    } catch (e) {
      print('Error unsubscribing: $e');
    }
  }

  /// Enable notifications on all notifiable custom characteristics
  Future<void> subscribeAllCustomNotifications(
      List<BluetoothService> services) async {
    for (var service in services) {
      final shortUuid = _getShortUuid(service.uuid);
      if (customServiceUuids.contains(shortUuid.toLowerCase())) {
        for (var char in service.characteristics) {
          if (char.properties.notify || char.properties.indicate) {
            try {
              subscribeCharacteristic(char);
              await Future.delayed(const Duration(milliseconds: 200));
            } catch (e) {
              print('Error subscribing custom char: $e');
            }
          }
        }
      }
    }
  }

  /// Try to read all readable custom characteristics
  Future<Map<String, List<int>>> readAllCustomCharacteristics(
      List<BluetoothService> services) async {
    final results = <String, List<int>>{};
    for (var service in services) {
      final shortUuid = _getShortUuid(service.uuid);
      if (customServiceUuids.contains(shortUuid.toLowerCase())) {
        for (var char in service.characteristics) {
          if (char.properties.read) {
            try {
              final value = await readCharacteristic(char);
              final charUuid = _getShortUuid(char.uuid);
              results['$shortUuid/$charUuid'] = value;
              await Future.delayed(const Duration(milliseconds: 100));
            } catch (e) {
              print('Error reading custom char: $e');
            }
          }
        }
      }
    }
    return results;
  }

  /// Try to parse incoming data as health metrics (generic heuristic)
  void _tryParseHealthData(
      BluetoothCharacteristic characteristic, List<int> data) {
    if (data.isEmpty) return;

    // Check if this is a HryFine protocol packet
    if (data[0] == HryProtocol.header || data[0] == HryProtocol.ackResponseHeader) {
      _handleNusData(data);
      return;
    }

    if (data.length >= 4) {
      final possibleSteps =
          data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
      if (possibleSteps > 0 && possibleSteps < 100000) {
        _currentHealth = _currentHealth.copyWith(steps: possibleSteps);
        if (data.length >= 8) {
          final possibleCalories =
              data[4] | (data[5] << 8) | (data[6] << 16) | (data[7] << 24);
          if (possibleCalories > 0 && possibleCalories < 50000) {
            _currentHealth = _currentHealth.copyWith(
                calories: possibleCalories / 10.0);
          }
        }
        if (data.length >= 12) {
          final possibleDistance =
              data[8] | (data[9] << 8) | (data[10] << 16) | (data[11] << 24);
          if (possibleDistance > 0 && possibleDistance < 1000000) {
            _currentHealth = _currentHealth.copyWith(
                distanceKm: possibleDistance / 1000.0);
          }
        }
        _healthDataController.add(_currentHealth);
      }
    }

    if (data.length == 1 && data[0] > 30 && data[0] < 250) {
      _currentHealth = _currentHealth.copyWith(heartRate: data[0]);
      _healthDataController.add(_currentHealth);
    }
  }

  void _emitCharacteristicValue(
      BluetoothCharacteristic characteristic, List<int> data) {
    _characteristicValueController.add(CharacteristicValue(
      serviceUuid: characteristic.serviceUuid.toString(),
      characteristicUuid: characteristic.uuid.toString(),
      rawValue: data,
      hexValue: _bytesToHex(data),
      stringValue: _bytesToString(data),
      timestamp: DateTime.now(),
    ));
  }

  /// Parse heart rate from standard Heart Rate Measurement
  int _parseStandardHeartRate(List<int> data) {
    if (data.isEmpty) return 0;
    final flags = data[0];
    if (flags & 0x01 == 0) {
      return data.length > 1 ? data[1] : 0;
    } else {
      return data.length > 2 ? (data[2] << 8) + data[1] : 0;
    }
  }

  /// Check if a UUID matches a short UUID
  bool _matchUuid(Guid uuid, String shortUuid) {
    return uuid.toString().toUpperCase().contains(shortUuid.toUpperCase());
  }

  /// Get short UUID (4 hex chars) from full UUID
  String _getShortUuid(Guid uuid) {
    final full = uuid.toString().toUpperCase();
    return full.length >= 8 ? full.substring(4, 8) : full;
  }

  /// Convert bytes to hex string
  static String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  String _bytesToHex(List<int> bytes) => bytesToHex(bytes);

  /// Convert bytes to readable string
  String _bytesToString(List<int> bytes) {
    try {
      final str = utf8.decode(bytes, allowMalformed: true);
      if (str.runes.every((r) => r >= 32 && r < 127)) {
        return str;
      }
      return _bytesToHex(bytes);
    } catch (_) {
      return _bytesToHex(bytes);
    }
  }

  /// Clean up all subscriptions
  void dispose() {
    stopAutoSync();
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _healthDataController.close();
    _batteryController.close();
    _deviceInfoController.close();
    _characteristicValueController.close();
    _protocolLogController.close();
  }

  /// Cancel all subscriptions without closing the streams
  void cancelSubscriptions() {
    stopAutoSync();
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _batteryLevel = -1;
    _currentHealth = HealthData();
    _deviceInfo = DeviceInfoData();
    _nusWriteChar = null;
    _nusNotifyChar = null;
    _receiveBuffer = null;
    _receivePos = 0;
    _isBound = false;
  }
}
