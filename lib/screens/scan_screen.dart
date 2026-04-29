import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/ble_scanner_service.dart';
import 'device_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with TickerProviderStateMixin {
  final BleScannerService _bleService = BleScannerService();
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  String? _errorMessage;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _scanningSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scanSubscription = _bleService.scanResults.listen((results) {
      setState(() {
        // Filter: only show devices with a name
        _scanResults = results
            .where((r) => r.device.platformName.isNotEmpty)
            .toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });

    _scanningSubscription = _bleService.isScanningStream.listen((scanning) {
      setState(() {
        _isScanning = scanning;
      });
      if (scanning) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanSubscription?.cancel();
    _scanningSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _errorMessage = null;
      _scanResults = [];
    });
    try {
      await _bleService.startScan();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _stopScan() async {
    await _bleService.stopScan();
  }

  void _connectToDevice(ScanResult result) async {
    await _stopScan();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceScreen(device: result.device),
      ),
    );
  }

  // Get signal strength icon based on RSSI
  IconData _getSignalIcon(int rssi) {
    if (rssi >= -60) return Icons.signal_cellular_4_bar;
    if (rssi >= -70) return Icons.signal_cellular_alt;
    if (rssi >= -80) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -60) return const Color(0xFF4CAF50);
    if (rssi >= -70) return const Color(0xFFFFC107);
    if (rssi >= -80) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
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
              _buildHeader(),
              if (_errorMessage != null) _buildErrorBanner(),
              Expanded(
                child: _scanResults.isEmpty
                    ? _buildEmptyState()
                    : _buildDeviceList(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildScanButton(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF3F8CFF)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C63FF).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.watch, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Epilepsy Monitor',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  _isScanning
                      ? 'Searching for devices...'
                      : '${_scanResults.length} devices found',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          if (_isScanning)
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF44336).withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF44336).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFF44336), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.outfit(
                color: const Color(0xFFF44336),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isScanning ? Icons.bluetooth_searching : Icons.bluetooth,
            size: 80,
            color: Colors.white24,
          ),
          const SizedBox(height: 24),
          Text(
            _isScanning ? 'Scanning...' : 'Tap SCAN to find devices',
            style: GoogleFonts.outfit(
              fontSize: 18,
              color: Colors.white38,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_isScanning) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: Color(0xFF6C63FF),
                strokeWidth: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _scanResults.length,
      itemBuilder: (context, index) {
        return _buildDeviceCard(_scanResults[index]);
      },
    );
  }

  Widget _buildDeviceCard(ScanResult result) {
    final deviceName = result.device.platformName;
    final rssi = result.rssi;
    final deviceId = result.device.remoteId.toString();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _connectToDevice(result),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: Row(
              children: [
                // Device icon
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3F8CFF)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.watch,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                // Device info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceName,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deviceId,
                        style: GoogleFonts.sourceCodePro(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
                // Signal strength
                Column(
                  children: [
                    Icon(
                      _getSignalIcon(rssi),
                      color: _getSignalColor(rssi),
                      size: 22,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$rssi dBm',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: _getSignalColor(rssi),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: Colors.white.withOpacity(0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (_isScanning ? const Color(0xFFF44336) : const Color(0xFF6C63FF))
                .withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: _isScanning ? _stopScan : _startScan,
        backgroundColor: _isScanning ? const Color(0xFFF44336) : const Color(0xFF6C63FF),
        icon: Icon(
          _isScanning ? Icons.stop : Icons.bluetooth_searching,
          color: Colors.white,
        ),
        label: Text(
          _isScanning ? 'STOP' : 'SCAN',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
