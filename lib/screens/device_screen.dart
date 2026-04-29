import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/ble_scanner_service.dart';
import 'health_dashboard_screen.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;
  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  final BleScannerService _bleService = BleScannerService();
  bool _isConnecting = true;
  bool _isConnected = false;
  String? _errorMessage;
  String _connectStatus = 'Connecting...';
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  bool _navigatedToDashboard = false;  // Don't disconnect if navigating forward

  @override
  void initState() {
    super.initState();
    _connectionSubscription = widget.device.connectionState.listen((state) {
      setState(() {
        _isConnected = state == BluetoothConnectionState.connected;
      });
    });
    _connect();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    // Only disconnect if we're going BACK, not forward to Dashboard
    if (!_navigatedToDashboard) {
      widget.device.disconnect();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _connectStatus = 'Connecting...';
    });

    try {
      await _bleService.connectWithRetry(
        widget.device,
        maxAttempts: 3,
        onStatus: (status) {
          if (mounted) setState(() => _connectStatus = status);
        },
      );
      final services = await _bleService.discoverServices(widget.device);

      setState(() {
        _isConnecting = false;
        _isConnected = true;
      });

      // Navigate to Health Dashboard after connection
      if (mounted) {
        _navigatedToDashboard = true;  // Mark: don't disconnect!
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HealthDashboardScreen(
              device: widget.device,
              services: services,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _errorMessage = 'Connection failed: ${e.toString()}';
      });
    }
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
              Expanded(
                child: _isConnecting
                    ? _buildConnectingState()
                    : _errorMessage != null
                        ? _buildErrorState()
                        : const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 24, 8),
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
                    Text(
                      widget.device.platformName.isNotEmpty
                          ? widget.device.platformName
                          : 'Unknown',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                    const Text('  ·  ',
                        style: TextStyle(color: Colors.white24, fontSize: 11)),
                    Expanded(
                      child: Text(
                        widget.device.remoteId.toString(),
                        style: GoogleFonts.sourceCodePro(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildConnectionBadge(),
        ],
      ),
    );
  }

  Widget _buildConnectionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isConnected
            ? const Color(0xFF4CAF50).withOpacity(0.15)
            : const Color(0xFFF44336).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isConnected
              ? const Color(0xFF4CAF50).withOpacity(0.3)
              : const Color(0xFFF44336).withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isConnected
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFF44336),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isConnected ? 'Connected' : 'Disconnected',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: _isConnected
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFF44336),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              color: Color(0xFF6C63FF),
              strokeWidth: 4,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _connectStatus,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 16,
              color: Colors.white54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Auto-retry with GATT cache clear',
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 64, color: Color(0xFFF44336)),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.refresh),
              label: Text('Retry', style: GoogleFonts.outfit()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
