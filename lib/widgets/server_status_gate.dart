import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/theme.dart';
import '../services/mbn_auth.dart';

enum ServerState { checking, online, offline, maintenance }

class ServerStatusGate extends StatefulWidget {
  const ServerStatusGate({
    super.key,
    required this.child,
    this.baseUrl = MbnAuth.defaultBaseUrl,
  });

  final Widget child;
  final String baseUrl;

  static void notifyMaintenance(Map<String, dynamic> data) {
    _instance?._onMaintenanceTriggered(data);
  }

  static bool bypassForTesting = false;
  static _ServerStatusGateState? _instance;

  @override
  State<ServerStatusGate> createState() => _ServerStatusGateState();
}

class _ServerStatusGateState extends State<ServerStatusGate> {
  ServerState _state = ServerState.checking;
  Map<String, dynamic>? _maintenanceData;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  int _serverTimeSkew = 0;
  Duration _currentPollInterval = const Duration(seconds: 10);
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    ServerStatusGate._instance = this;
    if (ServerStatusGate.bypassForTesting ||
        WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      _state = ServerState.online;
      return;
    }
    _checkServer();
    _pollTimer = Timer.periodic(_currentPollInterval, (_) => _pollServer());
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_state == ServerState.maintenance && _remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
        if (_remainingSeconds <= 0) {
          _pollServer();
        }
      }
    });
  }

  void _adjustPollInterval(Duration next) {
    if (_currentPollInterval == next) return;
    _currentPollInterval = next;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(next, (_) => _pollServer());
  }

  @override
  void dispose() {
    if (ServerStatusGate._instance == this) {
      ServerStatusGate._instance = null;
    }
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _onMaintenanceTriggered(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _maintenanceData = data;
      _calcRemaining(data);
      _state = ServerState.maintenance;
    });
    _adjustPollInterval(const Duration(seconds: 3));
  }

  void _calcRemaining(Map<String, dynamic> data) {
    final endsAt = (data['ends_at'] as num?)?.toInt() ?? 0;
    final serverTime = (data['server_time'] as num?)?.toInt();
    final localNow = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (serverTime != null) {
      _serverTimeSkew = serverTime - localNow;
    }
    final effectiveNow = localNow + _serverTimeSkew;
    if (endsAt > effectiveNow) {
      _remainingSeconds = endsAt - effectiveNow;
    } else {
      _remainingSeconds = 0;
    }
  }

  Future<void> _checkServer() async {
    setState(() => _retrying = true);
    try {
      final uri = Uri.parse('${widget.baseUrl}/api/maintenance');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 503) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final m = (data['maintenance'] as Map<String, dynamic>?) ?? data;
        final enabled = m['enabled'] == true;
        if (enabled) {
          _calcRemaining(m);
          if (_remainingSeconds > 0 || (m['ends_at'] as num? ?? 0) == 0) {
            setState(() {
              _maintenanceData = m;
              _state = ServerState.maintenance;
            });
            _adjustPollInterval(const Duration(seconds: 3));
            return;
          }
        }
        setState(() {
          _maintenanceData = null;
          _remainingSeconds = 0;
          _state = ServerState.online;
        });
        _adjustPollInterval(const Duration(seconds: 10));
      } else {
        setState(() => _state = ServerState.offline);
      }
    } catch (_) {
      if (mounted) setState(() => _state = ServerState.offline);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _pollServer() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/api/maintenance');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 503) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final m = (data['maintenance'] as Map<String, dynamic>?) ?? data;
        final enabled = m['enabled'] == true;
        if (enabled) {
          _calcRemaining(m);
          if (_remainingSeconds > 0 || (m['ends_at'] as num? ?? 0) == 0) {
            setState(() {
              _maintenanceData = m;
              _state = ServerState.maintenance;
            });
            _adjustPollInterval(const Duration(seconds: 3));
            return;
          }
        }
        // If maintenance is turned off or time elapsed:
        if (_state == ServerState.maintenance || _state == ServerState.checking || _state == ServerState.offline) {
          setState(() {
            _maintenanceData = null;
            _remainingSeconds = 0;
            _state = ServerState.online;
          });
          _adjustPollInterval(const Duration(seconds: 10));
        }
      }
    } catch (_) {}
  }

  String _formatTimer(int sec) {
    if (sec <= 0) return '00:00:00';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _buildCurrentState(),
    );
  }

  Widget _buildCurrentState() {
    switch (_state) {
      case ServerState.checking:
        return const Scaffold(
          backgroundColor: Color(0xFF0B0E14),
          body: Center(
            child: CircularProgressIndicator(color: MovieColors.orange),
          ),
        );
      case ServerState.offline:
        return Scaffold(
          backgroundColor: const Color(0xFF0B0E14),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: MovieColors.coral.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cloud_off_rounded,
                      size: 52,
                      color: MovieColors.coral,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'سرور در دسترس نیست',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'سرور در دسترس نیست لطفا بعدا امتحان کنید',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _retrying ? null : _checkServer,
                    icon: _retrying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('تلاش مجدد'),
                    style: FilledButton.styleFrom(
                      backgroundColor: MovieColors.orange,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case ServerState.maintenance:
        final msg = _maintenanceData?['message']?.toString() ?? 'سرور در حال بروزرسانی و تعمیرات است. لطفاً شکیبا باشید.';
        return Scaffold(
          backgroundColor: const Color(0xFF0B0E14),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: .12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.orange.withValues(alpha: .3), width: 2),
                    ),
                    child: const Icon(
                      Icons.engineering_rounded,
                      size: 58,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'حالت تعمیرات و بروزرسانی',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        height: 1.6,
                      ),
                    ),
                  ),
                  if (_remainingSeconds > 0) ...[
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.orange.withValues(alpha: .3)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'زمان باقیمانده تا بازگشایی خودکار:',
                            style: TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatTimer(_remainingSeconds),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                              color: Colors.orange,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'به محض پایان تعمیرات، برنامه خودبه‌خود باز می‌شود…',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      case ServerState.online:
        return widget.child;
    }
  }
}
