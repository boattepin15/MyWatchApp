import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'ble_data_service.dart';

/// Seizure risk level
enum SeizureRiskLevel { low, moderate, high }

/// A single seizure alert record
class SeizureAlert {
  final DateTime timestamp;
  final int heartRate;
  final String movementLevel;
  final double hrv;
  final SeizureRiskLevel riskLevel;

  SeizureAlert({
    required this.timestamp,
    required this.heartRate,
    required this.movementLevel,
    required this.hrv,
    required this.riskLevel,
  });
}

/// Service that monitors health data and triggers seizure alerts
class SeizureDetectionService {
  static final SeizureDetectionService _instance =
      SeizureDetectionService._internal();
  factory SeizureDetectionService() => _instance;
  SeizureDetectionService._internal();

  // Notification plugin
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Alert history
  final List<SeizureAlert> _alertHistory = [];
  List<SeizureAlert> get alertHistory => List.unmodifiable(_alertHistory);

  // Current risk level
  SeizureRiskLevel _currentRisk = SeizureRiskLevel.low;
  SeizureRiskLevel get currentRisk => _currentRisk;

  // Cooldown to prevent repeated alerts
  DateTime? _lastAlertTime;
  static const Duration _alertCooldown = Duration(seconds: 60);

  // Stream for risk level changes
  final _riskController = StreamController<SeizureRiskLevel>.broadcast();
  Stream<SeizureRiskLevel> get riskStream => _riskController.stream;

  // Stream for alert events
  final _alertController = StreamController<SeizureAlert>.broadcast();
  Stream<SeizureAlert> get alertStream => _alertController.stream;

  StreamSubscription? _healthSub;

  // ──────── Seizure Risk Thresholds (adjustable for testing) ────────
  int hrThreshold = 100;        // Heart Rate >= threshold bpm
  double hrvThreshold = 20.0;   // HRV <= threshold ms
  static const String movementThresholdHigh = 'High';

  /// Update thresholds (for testing)
  void setThresholds({int? hrThreshold, double? hrvThreshold}) {
    if (hrThreshold != null) this.hrThreshold = hrThreshold;
    if (hrvThreshold != null) this.hrvThreshold = hrvThreshold;
  }

  /// Initialize notification system
  Future<void> initialize() async {
    // Android settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);

    // Request notification permission (Android 13+)
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Start monitoring health data for seizure detection
  void startMonitoring(BleDataService dataService) {
    _healthSub?.cancel();
    _healthSub = dataService.healthDataStream.listen(_evaluateHealth);
  }

  /// Stop monitoring
  void stopMonitoring() {
    _healthSub?.cancel();
    _healthSub = null;
  }

  /// Evaluate health data for seizure risk
  void _evaluateHealth(HealthData data) {
    int riskScore = 0;

    // Check heart rate
    if (data.heartRate >= hrThreshold) riskScore++;

    // Check movement level
    if (data.movementLevel == movementThresholdHigh) riskScore++;

    // Check HRV (only if we have a valid value)
    if (data.hrv > 0 && data.hrv <= hrvThreshold) riskScore++;

    // Determine risk level
    SeizureRiskLevel newRisk;
    if (riskScore >= 3) {
      newRisk = SeizureRiskLevel.high;
    } else if (riskScore >= 2) {
      newRisk = SeizureRiskLevel.moderate;
    } else {
      newRisk = SeizureRiskLevel.low;
    }

    // Update if changed
    if (newRisk != _currentRisk) {
      _currentRisk = newRisk;
      _riskController.add(_currentRisk);
    }

    // Trigger alert for high risk
    if (newRisk == SeizureRiskLevel.high) {
      _triggerAlert(data);
    }
  }

  /// Trigger a seizure alert with notification
  Future<void> _triggerAlert(HealthData data) async {
    // Check cooldown
    final now = DateTime.now();
    if (_lastAlertTime != null &&
        now.difference(_lastAlertTime!) < _alertCooldown) {
      return; // Still in cooldown
    }
    _lastAlertTime = now;

    // Create alert record
    final alert = SeizureAlert(
      timestamp: now,
      heartRate: data.heartRate,
      movementLevel: data.movementLevel,
      hrv: data.hrv,
      riskLevel: SeizureRiskLevel.high,
    );

    _alertHistory.insert(0, alert);
    if (_alertHistory.length > 100) _alertHistory.removeLast();
    _alertController.add(alert);

    // Send notification
    await _sendNotification(alert);

    // Vibrate
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500], repeat: -1);
        // Stop after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          Vibration.cancel();
        });
      }
    } catch (_) {
      // Ignore vibration errors
    }
  }

  /// Send a local notification with health data details
  Future<void> _sendNotification(SeizureAlert alert) async {
    final bodyText =
        'Heart Rate: ${alert.heartRate} bpm\n'
        'Movement: ${alert.movementLevel}\n'
        'HRV: ${alert.hrv.toStringAsFixed(1)} ms\n'
        'ระดับความเสี่ยง: สูง';

    final androidDetails = AndroidNotificationDetails(
      'seizure_alerts',
      'Seizure Alerts',
      channelDescription: 'แจ้งเตือนเมื่อตรวจพบความเสี่ยงอาการชัก',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFF44336),
      styleInformation: BigTextStyleInformation(
        bodyText,
        contentTitle: '⚠️ ตรวจพบอาการชัก!',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      0, // Notification ID
      '⚠️ ตรวจพบอาการชัก!',
      bodyText,
      details,
    );
  }

  /// Get risk level display text in Thai
  static String riskLevelText(SeizureRiskLevel level) {
    switch (level) {
      case SeizureRiskLevel.low:
        return 'ต่ำ';
      case SeizureRiskLevel.moderate:
        return 'ปานกลาง';
      case SeizureRiskLevel.high:
        return 'สูง';
    }
  }

  /// Get risk level color
  static Color riskLevelColor(SeizureRiskLevel level) {
    switch (level) {
      case SeizureRiskLevel.low:
        return const Color(0xFF4CAF50); // Green
      case SeizureRiskLevel.moderate:
        return const Color(0xFFFF9800); // Orange
      case SeizureRiskLevel.high:
        return const Color(0xFFF44336); // Red
    }
  }

  /// Get risk level icon
  static IconData riskLevelIcon(SeizureRiskLevel level) {
    switch (level) {
      case SeizureRiskLevel.low:
        return Icons.check_circle;
      case SeizureRiskLevel.moderate:
        return Icons.warning_amber;
      case SeizureRiskLevel.high:
        return Icons.error;
    }
  }

  /// Force a test alert immediately (ignores cooldown), used for testing
  Future<void> triggerTestAlert({
    int? heartRate,
    String movementLevel = 'High',
    double? hrv,
  }) async {
    final testHr = heartRate ?? hrThreshold + 10;
    final testHrv = hrv ?? (hrvThreshold - 5).clamp(1.0, 999.0);
    final mockAlert = SeizureAlert(
      timestamp: DateTime.now(),
      heartRate: testHr,
      movementLevel: movementLevel,
      hrv: testHrv,
      riskLevel: SeizureRiskLevel.high,
    );

    _alertHistory.insert(0, mockAlert);
    if (_alertHistory.length > 100) _alertHistory.removeLast();
    _alertController.add(mockAlert);
    _currentRisk = SeizureRiskLevel.high;
    _riskController.add(_currentRisk);

    await _sendNotification(mockAlert);

    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
      }
    } catch (_) {}
  }

  void dispose() {
    _healthSub?.cancel();
    _riskController.close();
    _alertController.close();
  }
}
