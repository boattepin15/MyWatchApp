import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ble_data_service.dart';
import '../services/seizure_detection_service.dart';

class HealthDashboardScreen extends StatefulWidget {
  final BluetoothDevice device;
  final List<BluetoothService> services;

  const HealthDashboardScreen({
    super.key,
    required this.device,
    required this.services,
  });

  @override
  State<HealthDashboardScreen> createState() => _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends State<HealthDashboardScreen>
    with TickerProviderStateMixin {
  final BleDataService _dataService = BleDataService();
  final SeizureDetectionService _seizureService = SeizureDetectionService();

  int _batteryLevel = -1;
  DeviceInfoData _deviceInfo = DeviceInfoData();
  HealthData _healthData = HealthData();
  bool _isLoading = true;
  int _currentTab = 0; // 0 = Dashboard, 1 = Alerts, 2 = Explorer
  SeizureRiskLevel _seizureRisk = SeizureRiskLevel.low;
  List<SeizureAlert> _seizureAlerts = [];

  // Test panel state
  bool _showTestPanel = false;
  int _testHrThreshold = 100;
  double _testHrvThreshold = 20.0;
  bool _isSendingTest = false;

  // Animation
  late AnimationController _heartController;
  late Animation<double> _heartAnimation;

  // Explorer state
  final Map<String, List<int>> _characteristicValues = {};
  final Set<String> _notifyingChars = {};
  final Map<String, StreamSubscription> _charSubscriptions = {};

  // Command sender state
  final TextEditingController _hexController = TextEditingController();
  final List<_LogEntry> _responseLog = [];
  final ScrollController _logScrollController = ScrollController();

  // Subscriptions
  StreamSubscription? _healthSub;
  StreamSubscription? _batterySub;
  StreamSubscription? _charValueSub;
  StreamSubscription? _protocolLogSub;
  StreamSubscription? _seizureRiskSub;
  StreamSubscription? _seizureAlertSub;
  bool _hryProtocolStarted = false;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _heartAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.easeInOut),
    );

    _setupStreams();
    _loadInitialData();
  }

  void _setupStreams() {
    _healthSub = _dataService.healthDataStream.listen((data) {
      setState(() => _healthData = data);
    });
    _batterySub = _dataService.batteryStream.listen((level) {
      setState(() => _batteryLevel = level);
    });
    _charValueSub = _dataService.characteristicValueStream.listen((cv) {
      setState(() {
        _characteristicValues[cv.characteristicUuid] = cv.rawValue;
        _responseLog.insert(0, _LogEntry(
          time: DateTime.now(),
          uuid: cv.characteristicUuid,
          data: cv.rawValue,
          isIncoming: true,
        ));
        if (_responseLog.length > 200) _responseLog.removeLast();
      });
    });
    _protocolLogSub = _dataService.protocolLogStream.listen((msg) {
      setState(() {
        _responseLog.insert(0, _LogEntry(
          time: DateTime.now(),
          uuid: 'PROTO',
          data: [],
          isIncoming: true,
          message: msg,
        ));
        if (_responseLog.length > 300) _responseLog.removeLast();
      });
    });
    // Seizure detection streams
    _seizureRiskSub = _seizureService.riskStream.listen((risk) {
      setState(() => _seizureRisk = risk);
    });
    _seizureAlertSub = _seizureService.alertStream.listen((alert) {
      setState(() {
        _seizureAlerts = List.from(_seizureService.alertHistory);
      });
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    // ▶ Start HryFine protocol (Nordic UART Service)
    await _dataService.startHryProtocol(widget.services, device: widget.device);
    _hryProtocolStarted = _dataService.findNusService(widget.services);

    // Start seizure monitoring
    _seizureService.startMonitoring(_dataService);

    // Heart rate animation
    _heartController.repeat(reverse: true);

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _heartController.dispose();
    _healthSub?.cancel();
    _batterySub?.cancel();
    _charValueSub?.cancel();
    _protocolLogSub?.cancel();
    _seizureRiskSub?.cancel();
    _seizureAlertSub?.cancel();
    _seizureService.stopMonitoring();
    _hexController.dispose();
    _logScrollController.dispose();
    for (var sub in _charSubscriptions.values) {
      sub.cancel();
    }
    _dataService.cancelSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B2838),
              Color(0xFF16213E),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              _buildTabBar(),
              Expanded(
                child: _isLoading
                    ? _buildLoadingState()
                    : _currentTab == 0
                        ? _buildDashboard()
                        : _currentTab == 1
                            ? _buildAlertsTab()
                            : _buildExplorer(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Epilepsy Monitor',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    if (widget.device.platformName.isNotEmpty) ...[
                      Text(
                        widget.device.platformName,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                      const Text('  ·  ',
                          style:
                              TextStyle(color: Colors.white24, fontSize: 11)),
                    ],
                    Text(
                      'Health Dashboard',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Battery badge
          if (_batteryLevel >= 0) _buildBatteryBadge(),
        ],
      ),
    );
  }

  Widget _buildBatteryBadge() {
    final color = _batteryLevel > 50
        ? const Color(0xFF4CAF50)
        : _batteryLevel > 20
            ? const Color(0xFFFFC107)
            : const Color(0xFFF44336);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _batteryLevel > 80
                ? Icons.battery_full
                : _batteryLevel > 50
                    ? Icons.battery_5_bar
                    : _batteryLevel > 20
                        ? Icons.battery_3_bar
                        : Icons.battery_1_bar,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            '$_batteryLevel%',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _buildTab('Dashboard', Icons.dashboard_rounded, 0),
            _buildTab('Alerts', Icons.warning_amber_rounded, 1),
            _buildTab('Explorer', Icons.manage_search_rounded, 2),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, IconData icon, int index) {
    final isActive = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF6C63FF).withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: isActive ? const Color(0xFF6C63FF) : Colors.white38),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? Colors.white : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              color: Color(0xFF6C63FF),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Reading device data...',
            style: GoogleFonts.outfit(
              fontSize: 16,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== DASHBOARD TAB ====================

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Seizure Risk Card
          _buildSeizureRiskCard(),
          const SizedBox(height: 12),
          // Heart Rate - large card
          _buildHeartRateCard(),
          const SizedBox(height: 12),
          // Blood Pressure + SpO2 row
          Row(
            children: [
              Expanded(child: _buildBloodPressureCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildSpO2Card()),
            ],
          ),
          const SizedBox(height: 12),
          // Temperature card (full width)
          _buildTemperatureCard(),
          const SizedBox(height: 12),
          // Steps + Calories row
          Row(
            children: [
              Expanded(child: _buildStepsCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildCaloriesCard()),
            ],
          ),
          const SizedBox(height: 12),
          // Distance + Goal row
          Row(
            children: [
              Expanded(child: _buildDistanceCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildGoalCard()),
            ],
          ),
          const SizedBox(height: 12),
          // Device Info card
          _buildDeviceInfoCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSeizureRiskCard() {
    final riskColor = SeizureDetectionService.riskLevelColor(_seizureRisk);
    final riskText = SeizureDetectionService.riskLevelText(_seizureRisk);
    final riskIcon = SeizureDetectionService.riskLevelIcon(_seizureRisk);
    final isHigh = _seizureRisk == SeizureRiskLevel.high;
    final hr = _healthData.heartRate;
    final hrv = _healthData.hrv;
    final movement = _healthData.movementLevel;

    return _buildGlassCard(
      gradient: [
        riskColor.withOpacity(isHigh ? 0.35 : 0.15),
        riskColor.withOpacity(0.05),
      ],
      borderColor: riskColor.withOpacity(isHigh ? 0.6 : 0.25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Icon(riskIcon, color: riskColor, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seizure Risk',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'ระดับความเสี่ยงอาการชัก',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
                // Risk Level Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: riskColor.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isHigh)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SizedBox(
                            width: 10,
                            height: 10,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: riskColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: riskColor.withOpacity(0.6),
                                    blurRadius: 6,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Text(
                        riskText,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: riskColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isHigh) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: riskColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: riskColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ตรวจพบอาการชัก! กรุณาตรวจสอบผู้ป่วย',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: riskColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            // Health data row
            Row(
              children: [
                _buildSeizureMetric(
                  'Heart Rate',
                  hr > 0 ? '$hr bpm' : '--',
                  Icons.favorite,
                  hr >= _seizureService.hrThreshold
                      ? const Color(0xFFF44336)
                      : const Color(0xFF4CAF50),
                ),
                const SizedBox(width: 8),
                _buildSeizureMetric(
                  'Movement',
                  movement,
                  Icons.directions_run,
                  movement == 'High'
                      ? const Color(0xFFF44336)
                      : movement == 'Medium'
                          ? const Color(0xFFFF9800)
                          : const Color(0xFF4CAF50),
                ),
                const SizedBox(width: 8),
                _buildSeizureMetric(
                  'HRV',
                  hrv > 0 ? '${hrv.toStringAsFixed(0)} ms' : '--',
                  Icons.timeline,
                  hrv > 0 && hrv <= _seizureService.hrvThreshold
                      ? const Color(0xFFF44336)
                      : const Color(0xFF4CAF50),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Risk level indicator bar
            Row(
              children: [
                _buildRiskDot('Low', SeizureRiskLevel.low),
                Expanded(
                  child: Container(
                    height: 3,
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                _buildRiskDot('Moderate', SeizureRiskLevel.moderate),
                Expanded(
                  child: Container(
                    height: 3,
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                _buildRiskDot('High', SeizureRiskLevel.high),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeizureMetric(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 10,
                color: Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskDot(String label, SeizureRiskLevel level) {
    final isActive = _seizureRisk == level ||
        (_seizureRisk == SeizureRiskLevel.high) ||
        (_seizureRisk == SeizureRiskLevel.moderate &&
            level != SeizureRiskLevel.high);
    final color = SeizureDetectionService.riskLevelColor(level);

    return Column(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? color : Colors.white.withOpacity(0.15),
            border: Border.all(
              color: _seizureRisk == level
                  ? color
                  : Colors.white.withOpacity(0.1),
              width: _seizureRisk == level ? 2 : 1,
            ),
            boxShadow: _seizureRisk == level
                ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 9,
            color:
                _seizureRisk == level ? Colors.white70 : Colors.white24,
            fontWeight: _seizureRisk == level
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ==================== ALERTS TAB ====================

  Widget _buildAlertsTab() {
    return Column(
      children: [
        // ─── Test Panel ───
        _buildTestPanel(),
        // ─── Alert History ───
        Expanded(
          child: _seizureAlerts.isEmpty
              ? _buildEmptyAlerts()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _seizureAlerts.length,
                  itemBuilder: (context, index) {
                    final alert = _seizureAlerts[index];
                    final color = SeizureDetectionService.riskLevelColor(alert.riskLevel);
                    final t = alert.timestamp;
                    final timeStr =
                        '${t.day}/${t.month}/${t.year} '
                        '${t.hour.toString().padLeft(2, '0')}:'
                        '${t.minute.toString().padLeft(2, '0')}:'
                        '${t.second.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildGlassCard(
                        gradient: [
                          color.withOpacity(0.2),
                          color.withOpacity(0.05),
                        ],
                        borderColor: color.withOpacity(0.3),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning, color: color, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '⚠️ ตรวจพบอาการชัก',
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    timeStr,
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _buildAlertDetailRow('Heart Rate',
                                  '${alert.heartRate} bpm', Icons.favorite),
                              const SizedBox(height: 4),
                              _buildAlertDetailRow('Movement',
                                  alert.movementLevel, Icons.directions_run),
                              const SizedBox(height: 4),
                              _buildAlertDetailRow('HRV',
                                  '${alert.hrv.toStringAsFixed(1)} ms', Icons.timeline),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyAlerts() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text(
            'ไม่มีการแจ้งเตือน',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ระบบจะบันทึกเมื่อตรวจพบอาการชัก',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _buildGlassCard(
        gradient: [
          const Color(0xFF6C63FF).withOpacity(0.18),
          const Color(0xFF6C63FF).withOpacity(0.04),
        ],
        borderColor: const Color(0xFF6C63FF).withOpacity(0.35),
        child: Column(
          children: [
            // Header — tap to expand/collapse
            GestureDetector(
              onTap: () => setState(() => _showTestPanel = !_showTestPanel),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.science_rounded,
                        color: Color(0xFF6C63FF), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🧪 ทดสอบการแจ้งเตือน',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'ปรับค่าเกณฑ์ แล้วกดทดสอบ',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _showTestPanel
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white38,
                    ),
                  ],
                ),
              ),
            ),
            // Expanded content
            if (_showTestPanel)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(
                        color: Colors.white.withOpacity(0.08),
                        height: 1),
                    const SizedBox(height: 14),

                    // ── Heart Rate Threshold ──
                    Row(
                      children: [
                        const Icon(Icons.favorite,
                            size: 16, color: Color(0xFFE91E63)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'HR Threshold: ≥ $_testHrThreshold bpm',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: const Color(0xFFE91E63),
                        thumbColor: const Color(0xFFE91E63),
                        inactiveTrackColor:
                            Colors.white.withOpacity(0.12),
                        overlayColor:
                            const Color(0xFFE91E63).withOpacity(0.12),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        min: 40,
                        max: 200,
                        divisions: 32,
                        value: _testHrThreshold.toDouble(),
                        onChanged: (v) => setState(
                            () => _testHrThreshold = v.round()),
                      ),
                    ),
                    // Quick select HR buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [60, 80, 100, 120, 150].map((v) {
                        final active = _testHrThreshold == v;
                        return GestureDetector(
                          onTap: () => setState(
                              () => _testHrThreshold = v),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFFE91E63)
                                      .withOpacity(0.3)
                                  : Colors.white.withOpacity(0.06),
                              borderRadius:
                                  BorderRadius.circular(8),
                              border: Border.all(
                                color: active
                                    ? const Color(0xFFE91E63)
                                        .withOpacity(0.5)
                                    : Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Text(
                              '≥$v',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? const Color(0xFFE91E63)
                                    : Colors.white38,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // ── HRV Threshold ──
                    Row(
                      children: [
                        const Icon(Icons.timeline,
                            size: 16, color: Color(0xFF3F8CFF)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'HRV Threshold: ≤ ${_testHrvThreshold.toStringAsFixed(0)} ms',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: const Color(0xFF3F8CFF),
                        thumbColor: const Color(0xFF3F8CFF),
                        inactiveTrackColor:
                            Colors.white.withOpacity(0.12),
                        overlayColor:
                            const Color(0xFF3F8CFF).withOpacity(0.12),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        min: 5,
                        max: 100,
                        divisions: 19,
                        value: _testHrvThreshold,
                        onChanged: (v) => setState(
                            () => _testHrvThreshold = v.roundToDouble()),
                      ),
                    ),
                    // Quick select HRV buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [10.0, 20.0, 30.0, 50.0, 100.0].map((v) {
                        final active = _testHrvThreshold == v;
                        return GestureDetector(
                          onTap: () => setState(
                              () => _testHrvThreshold = v),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFF3F8CFF)
                                      .withOpacity(0.3)
                                  : Colors.white.withOpacity(0.06),
                              borderRadius:
                                  BorderRadius.circular(8),
                              border: Border.all(
                                color: active
                                    ? const Color(0xFF3F8CFF)
                                        .withOpacity(0.5)
                                    : Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Text(
                              '≤${v.toInt()}',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? const Color(0xFF3F8CFF)
                                    : Colors.white38,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // ── Trigger Button ──
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSendingTest
                            ? null
                            : () async {
                                setState(() => _isSendingTest = true);
                                // Apply thresholds
                                _seizureService.setThresholds(
                                  hrThreshold: _testHrThreshold,
                                  hrvThreshold: _testHrvThreshold,
                                );
                                // Trigger test
                                await _seizureService.triggerTestAlert(
                                  heartRate: _testHrThreshold + 5,
                                  movementLevel: 'High',
                                  hrv: (_testHrvThreshold - 3.0).clamp(1.0, 999.0),
                                );
                                setState(() => _isSendingTest = false);
                              },
                        icon: _isSendingTest
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ))
                            : const Icon(Icons.notifications_active_rounded),
                        label: Text(
                          _isSendingTest ? 'กำลังส่ง...' : 'ทดสอบการแจ้งเตือน',
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.outfit(fontSize: 12, color: Colors.white38),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildHeartRateCard() {
    final hr = _healthData.heartRate;
    return _buildGlassCard(
      gradient: [
        const Color(0xFFE91E63).withOpacity(0.2),
        const Color(0xFFE91E63).withOpacity(0.05),
      ],
      borderColor: const Color(0xFFE91E63).withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _heartAnimation,
                  child: const Icon(
                    Icons.favorite,
                    color: Color(0xFFE91E63),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Heart Rate',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hr > 0 ? '$hr' : '--',
                  style: GoogleFonts.outfit(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 6),
                  child: Text(
                    'BPM',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      color: Colors.white38,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsCard() {
    return _buildGlassCard(
      gradient: [
        const Color(0xFF4CAF50).withOpacity(0.2),
        const Color(0xFF4CAF50).withOpacity(0.05),
      ],
      borderColor: const Color(0xFF4CAF50).withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_walk,
                    color: Color(0xFF4CAF50), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Steps',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _healthData.steps > 0 ? '${_healthData.steps}' : '--',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _healthData.steps / _healthData.goal,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF4CAF50)),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '/ ${_healthData.goal}',
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaloriesCard() {
    return _buildGlassCard(
      gradient: [
        const Color(0xFFFF9800).withOpacity(0.2),
        const Color(0xFFFF9800).withOpacity(0.05),
      ],
      borderColor: const Color(0xFFFF9800).withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_fire_department,
                    color: Color(0xFFFF9800), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Calories',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _healthData.calories > 0
                  ? _healthData.calories.toStringAsFixed(1)
                  : '--',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'kcal',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistanceCard() {
    return _buildGlassCard(
      gradient: [
        const Color(0xFF3F8CFF).withOpacity(0.2),
        const Color(0xFF3F8CFF).withOpacity(0.05),
      ],
      borderColor: const Color(0xFF3F8CFF).withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.straighten,
                    color: Color(0xFF3F8CFF), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Distance',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _healthData.distanceKm > 0
                  ? _healthData.distanceKm.toStringAsFixed(2)
                  : '--',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'km',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalCard() {
    final progress = _healthData.goal > 0
        ? (_healthData.steps / _healthData.goal * 100).clamp(0, 100)
        : 0.0;

    return _buildGlassCard(
      gradient: [
        const Color(0xFF9C27B0).withOpacity(0.2),
        const Color(0xFF9C27B0).withOpacity(0.05),
      ],
      borderColor: const Color(0xFF9C27B0).withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_rounded,
                    color: Color(0xFF9C27B0), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Goal',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${progress.toStringAsFixed(0)}%',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF9C27B0)),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_healthData.goal} steps',
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBloodPressureCard() {
    final sys = _healthData.systolic;
    final dia = _healthData.diastolic;
    return _buildGlassCard(
      gradient: [
        const Color(0xFFFF5722).withOpacity(0.2),
        const Color(0xFFFF5722).withOpacity(0.05),
      ],
      borderColor: const Color(0xFFFF5722).withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bloodtype,
                    color: Color(0xFFFF5722), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Blood Pressure',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              sys > 0 ? '$sys/$dia' : '--/--',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'mmHg',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpO2Card() {
    final spo2 = _healthData.bloodOxygen;
    final color = spo2 >= 95
        ? const Color(0xFF00BCD4)
        : spo2 > 0
            ? const Color(0xFFFF9800)
            : const Color(0xFF00BCD4);
    return _buildGlassCard(
      gradient: [
        color.withOpacity(0.2),
        color.withOpacity(0.05),
      ],
      borderColor: color.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.air, color: color, size: 22),
                const SizedBox(width: 8),
                Text(
                  'SpO2',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              spo2 > 0 ? '$spo2' : '--',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '%',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemperatureCard() {
    final temp = _healthData.temperature;
    return _buildGlassCard(
      gradient: [
        const Color(0xFFFF6F00).withOpacity(0.15),
        const Color(0xFFFF6F00).withOpacity(0.05),
      ],
      borderColor: const Color(0xFFFF6F00).withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.thermostat,
                color: Color(0xFFFF6F00), size: 28),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Temperature',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  temp > 0 ? '${temp.toStringAsFixed(1)} °C' : '-- °C',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    return _buildGlassCard(
      gradient: [
        Colors.white.withOpacity(0.06),
        Colors.white.withOpacity(0.02),
      ],
      borderColor: Colors.white.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline,
                    color: Color(0xFF6C63FF), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Device Information',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Model', _deviceInfo.modelNumber),
            _buildInfoRow('Firmware', _deviceInfo.firmwareRevision),
            _buildInfoRow('Hardware', _deviceInfo.hardwareRevision),
            _buildInfoRow('Manufacturer', _deviceInfo.manufacturer),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.white38,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.sourceCodePro(
                fontSize: 12,
                color: Colors.white60,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== EXPLORER TAB ====================

  Widget _buildExplorer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Command Sender Section
          _buildCommandSender(),
          const SizedBox(height: 12),
          // Response Log
          _buildResponseLog(),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Services (${widget.services.length})',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ),
          ...widget.services
              .map((service) => _buildExplorerServiceCard(service)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==================== COMMAND SENDER ====================


  Widget _buildCommandSender() {
    // Collect all writable custom characteristics
    final writableChars = <BluetoothCharacteristic>[];
    for (var service in widget.services) {
      for (var char in service.characteristics) {
        if (char.properties.write || char.properties.writeWithoutResponse) {
          writableChars.add(char);
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF9800).withOpacity(0.1),
            const Color(0xFFFF9800).withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.send_rounded, color: Color(0xFFFF9800), size: 20),
              const SizedBox(width: 8),
              Text(
                'HryFine Protocol',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              // NUS status indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _hryProtocolStarted
                      ? const Color(0xFF4CAF50).withOpacity(0.2)
                      : const Color(0xFFF44336).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _hryProtocolStarted ? 'NUS ✓' : 'NUS ✗',
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 10,
                    color: _hryProtocolStarted
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFF44336),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ──── HryFine Quick Commands ────
          Text(
            'Health Data Commands:',
            style: GoogleFonts.outfit(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildHryButton('📊 Sync All', HryProtocol.syncAllHistory(), const Color(0xFF6C63FF)),
              _buildHryButton('📊 Today', HryProtocol.syncTodayHistory(), const Color(0xFF6C63FF)),
              _buildHryButton('🏃 Steps ON', HryProtocol.enableRealTimeSteps(), const Color(0xFF4CAF50)),
              _buildHryButton('🏃 Steps OFF', HryProtocol.disableRealTimeSteps(), const Color(0xFF9E9E9E)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Device Commands:',
            style: GoogleFonts.outfit(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildHryButton('ℹ️ Device Info', HryProtocol.requestDeviceInfo(), const Color(0xFF2196F3)),
              _buildHryButton('⚙️ Settings', HryProtocol.requestSettings(), const Color(0xFF2196F3)),
              _buildHryButton('🔗 Bind', HryProtocol.bindDevice('FlutterU'), const Color(0xFFFF9800)),
              _buildHryButton('🔧 Features', HryProtocol.requestFeatures(), const Color(0xFF2196F3)),
              _buildHryButton('⏰ Alarm', HryProtocol.requestAlarmClock(), const Color(0xFF9C27B0)),
            ],
          ),
          const SizedBox(height: 12),
          // Custom hex input
          Text(
            'Custom HEX (raw):',
            style: GoogleFonts.outfit(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hexController,
                  style: GoogleFonts.sourceCodePro(fontSize: 13, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'DF 00 05 05 01 01 00 00',
                    hintStyle: GoogleFonts.sourceCodePro(fontSize: 12, color: Colors.white24),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _sendCustomHex(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9800),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('SEND', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHryButton(String label, List<int> command, Color color) {
    return InkWell(
      onTap: () => _sendHryCommand(command),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _sendHryCommand(List<int> command) {
    setState(() {
      _responseLog.insert(0, _LogEntry(
        time: DateTime.now(),
        uuid: 'SENT',
        data: command,
        isIncoming: false,
      ));
      if (_responseLog.length > 300) _responseLog.removeLast();
    });
    _dataService.writeNusCommand(command);
  }

  void _sendCustomHex() {
    final hex = _hexController.text.trim();
    if (hex.isEmpty) return;
    try {
      final bytes = hex
          .split(RegExp(r'[\s,]'))
          .where((s) => s.isNotEmpty)
          .map((s) => int.parse(s, radix: 16))
          .toList();
      _sendHryCommand(bytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid hex format: $e'),
          backgroundColor: const Color(0xFFF44336),
        ),
      );
    }
  }





  Widget _buildResponseLog() {
    if (_responseLog.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, color: Color(0xFF4CAF50), size: 16),
              const SizedBox(width: 6),
              Text(
                'Live Log',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white54,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: _exportLog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3F8CFF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.share, size: 12, color: Color(0xFF3F8CFF)),
                      const SizedBox(width: 4),
                      Text(
                        'EXPORT',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: const Color(0xFF3F8CFF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _responseLog.clear()),
                child: Text(
                  'CLEAR',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    color: Colors.white30,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 250,
            child: ListView.builder(
              controller: _logScrollController,
              itemCount: _responseLog.length,
              itemBuilder: (context, index) {
                final entry = _responseLog[index];
                final timeStr =
                    '${entry.time.hour.toString().padLeft(2, '0')}:'
                    '${entry.time.minute.toString().padLeft(2, '0')}:'
                    '${entry.time.second.toString().padLeft(2, '0')}';
                final hexStr = entry.message ?? BleDataService.bytesToHex(entry.data);
                final isProto = entry.uuid == 'PROTO';
                final shortUuid = isProto ? '' : (entry.uuid.length >= 8
                    ? entry.uuid.toUpperCase().substring(4, 8)
                    : entry.uuid);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '$timeStr ',
                        style: GoogleFonts.sourceCodePro(
                          fontSize: 10, color: Colors.white24,
                        ),
                      ),
                      if (!isProto) ...[
                        TextSpan(
                          text: entry.isIncoming ? '◀ ' : '▶ ',
                          style: GoogleFonts.sourceCodePro(
                            fontSize: 10,
                            color: entry.isIncoming
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFFF9800),
                          ),
                        ),
                        TextSpan(
                          text: '[$shortUuid] ',
                          style: GoogleFonts.sourceCodePro(
                            fontSize: 10, color: Colors.white38,
                          ),
                        ),
                      ],
                      TextSpan(
                        text: hexStr,
                        style: GoogleFonts.sourceCodePro(
                          fontSize: 10,
                          color: isProto
                              ? const Color(0xFF64B5F6)
                              : entry.isIncoming
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFFF9800),
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLog() async {
    if (_responseLog.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('=== BLE Communication Log ===');
    buffer.writeln('Device: ${widget.device.platformName} (${widget.device.remoteId})');
    buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total entries: ${_responseLog.length}');
    buffer.writeln('=============================');
    buffer.writeln();

    // Services summary
    buffer.writeln('--- Services ---');
    for (var service in widget.services) {
      final uuid = service.uuid.toString().toUpperCase();
      final shortUuid = uuid.length >= 8 ? uuid.substring(4, 8) : uuid;
      buffer.writeln('Service 0x$shortUuid (${service.characteristics.length} chars):');
      for (var char in service.characteristics) {
        final charUuid = char.uuid.toString().toUpperCase();
        final charShort = charUuid.length >= 8 ? charUuid.substring(4, 8) : charUuid;
        final props = <String>[];
        if (char.properties.read) props.add('READ');
        if (char.properties.write) props.add('WRITE');
        if (char.properties.writeWithoutResponse) props.add('WRITE_NR');
        if (char.properties.notify) props.add('NOTIFY');
        if (char.properties.indicate) props.add('INDICATE');
        buffer.writeln('  └ 0x$charShort [${props.join(", ")}]');

        // Include last known value
        final val = _characteristicValues[char.uuid.toString()];
        if (val != null && val.isNotEmpty) {
          buffer.writeln('    Value: ${BleDataService.bytesToHex(val)}');
          buffer.writeln('    DEC:   ${val.join(", ")}');
        }
      }
      buffer.writeln();
    }

    buffer.writeln('--- Communication Log ---');
    // Reverse so oldest first
    for (var entry in _responseLog.reversed) {
      final timeStr =
          '${entry.time.hour.toString().padLeft(2, '0')}:'
          '${entry.time.minute.toString().padLeft(2, '0')}:'
          '${entry.time.second.toString().padLeft(2, '0')}.'
          '${entry.time.millisecond.toString().padLeft(3, '0')}';
      final direction = entry.isIncoming ? 'RX' : 'TX';
      final shortUuid = entry.uuid.length >= 8
          ? entry.uuid.toUpperCase().substring(4, 8)
          : entry.uuid;
      final content = entry.message ?? BleDataService.bytesToHex(entry.data);
      buffer.writeln('$timeStr [$direction] [$shortUuid] $content');
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${dir.path}/ble_log_$timestamp.txt');
      await file.writeAsString(buffer.toString());

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'BLE Log - ${widget.device.platformName}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: const Color(0xFFF44336),
          ),
        );
      }
    }
  }

  Widget _buildExplorerServiceCard(BluetoothService service) {
    final uuid = service.uuid.toString().toUpperCase();
    final shortUuid = uuid.length >= 8 ? uuid.substring(4, 8) : uuid;
    final serviceName = _getServiceName(shortUuid);
    final isCustom =
        BleDataService.customServiceUuids.contains(shortUuid.toLowerCase());

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCustom
              ? const Color(0xFFFF9800).withOpacity(0.15)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        iconColor: Colors.white38,
        collapsedIconColor: Colors.white24,
        leading: Icon(
          isCustom ? Icons.extension : Icons.miscellaneous_services,
          color: isCustom ? const Color(0xFFFF9800) : const Color(0xFF6C63FF),
          size: 20,
        ),
        title: Text(
          serviceName,
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          '0x$shortUuid · ${service.characteristics.length} chars',
          style: GoogleFonts.sourceCodePro(
            fontSize: 11,
            color: isCustom
                ? const Color(0xFFFF9800).withOpacity(0.5)
                : Colors.white30,
          ),
        ),
        children: service.characteristics
            .map((c) => _buildExplorerCharacteristic(c))
            .toList(),
      ),
    );
  }

  Widget _buildExplorerCharacteristic(BluetoothCharacteristic char) {
    final uuid = char.uuid.toString().toUpperCase();
    final shortUuid = uuid.length >= 8 ? uuid.substring(4, 8) : uuid;
    final fullUuid = char.uuid.toString();
    final properties = <String>[];
    if (char.properties.read) properties.add('READ');
    if (char.properties.write) properties.add('WRITE');
    if (char.properties.writeWithoutResponse) properties.add('WRITE_NR');
    if (char.properties.notify) properties.add('NOTIFY');
    if (char.properties.indicate) properties.add('INDICATE');

    final hasValue = _characteristicValues.containsKey(fullUuid);
    final value = _characteristicValues[fullUuid];
    final isNotifying = _notifyingChars.contains(fullUuid);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: isNotifying
            ? Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isNotifying
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF3F8CFF),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '0x$shortUuid',
                style: GoogleFonts.sourceCodePro(
                  fontSize: 13,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Action buttons
              if (char.properties.read)
                _buildActionButton(
                  'READ',
                  Icons.download_rounded,
                  const Color(0xFF3F8CFF),
                  () => _readCharValue(char),
                ),
              if (char.properties.notify || char.properties.indicate)
                _buildActionButton(
                  isNotifying ? 'STOP' : 'NOTIFY',
                  isNotifying
                      ? Icons.notifications_off
                      : Icons.notifications_active,
                  isNotifying
                      ? const Color(0xFFF44336)
                      : const Color(0xFF4CAF50),
                  () => _toggleNotify(char),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Properties
          Text(
            properties.join(' · '),
            style: GoogleFonts.outfit(
              fontSize: 10,
              color: const Color(0xFF3F8CFF).withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          // Value display
          if (hasValue && value != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HEX: ${BleDataService.bytesToHex(value)}',
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 11,
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'DEC: ${value.join(', ')}',
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 11,
                      color: Colors.white38,
                    ),
                  ),
                  if (_tryDecodeString(value) != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'STR: ${_tryDecodeString(value)}',
                      style: GoogleFonts.sourceCodePro(
                        fontSize: 11,
                        color: const Color(0xFFFFC107),
                      ),
                    ),
                  ],
                  Text(
                    '(${value.length} bytes)',
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 10,
                      color: Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _readCharValue(BluetoothCharacteristic char) async {
    final value = await _dataService.readCharacteristic(char);
    setState(() {
      _characteristicValues[char.uuid.toString()] = value;
    });
  }

  void _toggleNotify(BluetoothCharacteristic char) {
    final uuid = char.uuid.toString();
    if (_notifyingChars.contains(uuid)) {
      // Stop notify
      _dataService.unsubscribeCharacteristic(char);
      _charSubscriptions[uuid]?.cancel();
      _charSubscriptions.remove(uuid);
      setState(() => _notifyingChars.remove(uuid));
    } else {
      // Start notify
      final sub = _dataService.subscribeCharacteristic(char);
      if (sub != null) {
        _charSubscriptions[uuid] = sub;
        setState(() => _notifyingChars.add(uuid));
      }
    }
  }

  String? _tryDecodeString(List<int> bytes) {
    try {
      final str = String.fromCharCodes(bytes);
      if (str.runes.every((r) => r >= 32 && r < 127)) {
        return str;
      }
    } catch (_) {}
    return null;
  }

  // ==================== HELPERS ====================

  Widget _buildGlassCard({
    required List<Color> gradient,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  String _getServiceName(String shortUuid) {
    const serviceNames = {
      '1800': 'Generic Access',
      '1801': 'Generic Attribute',
      '180A': 'Device Information',
      '180D': '❤️ Heart Rate',
      '180F': '🔋 Battery',
      '1802': 'Immediate Alert',
      '1803': 'Link Loss',
      '1804': 'Tx Power',
      '1805': 'Current Time',
      '1811': 'Alert Notification',
      'FF10': '⚙️ Custom (FF10)',
      'FF12': '⚙️ Custom (FF12)',
      'FF00': '⚙️ Custom (FF00)',
      '0001': '⚙️ Custom (0001)',
    };
    return serviceNames[shortUuid.toUpperCase()] ?? 'Service ($shortUuid)';
  }
}

class _LogEntry {
  final DateTime time;
  final String uuid;
  final List<int> data;
  final bool isIncoming;
  final String? message;

  _LogEntry({
    required this.time,
    required this.uuid,
    required this.data,
    required this.isIncoming,
    this.message,
  });
}
