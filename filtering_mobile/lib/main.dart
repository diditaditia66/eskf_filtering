import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/sensors_service.dart';
import 'services/fusion_service.dart';
import 'services/transport_service.dart';
import 'services/log_service.dart';

import 'screens/log_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/map_screen.dart';

const _kWsUrlPrefKey = 'ws_url';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const FilteringApp());
}

class FilteringApp extends StatelessWidget {
  const FilteringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESKF Filtering',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[50],
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: const FilteringHome(),
    );
  }
}

class FilteringHome extends StatefulWidget {
  const FilteringHome({super.key});
  @override
  State<FilteringHome> createState() => _FilteringHomeState();
}

class _FilteringHomeState extends State<FilteringHome> {
  String _wsUrl = 'ws://10.50.172.248:8765';
  late final SensorsService _sensors;
  late final FusionService _fusion;
  late final TransportService _transport;
  late final LogService _log;

  StreamSubscription<GpsCompassSample>? _rawSub;
  StreamSubscription<FilteredOutput>? _fusedSub;
  StreamSubscription<bool>? _wsConnSub;

  // HUD
  StreamSubscription<FusionHealth>? _healthSub;
  StreamSubscription<double>? _rttSub;
  double? _lastRttMs;
  int _queueLen = 0;
  double _emaSigma = 0.0;
  double _lastDt = 0.0;
  int _gpsAcc = 0, _gpsRej = 0, _hdgAcc = 0, _hdgRej = 0;

  bool _running = false;
  bool _wsConnected = false;
  int _gpsDistanceFilterM = 1;

  @override
  void initState() {
    super.initState();
    _sensors = SensorsService();
    _fusion = FusionService(sensors: _sensors);
    _transport = TransportService();
    _log = LogService();

    _wsConnSub = _transport.connectedStream.listen((ok) {
      if (!mounted) return;
      setState(() => _wsConnected = ok);
    });

    // HUD subscriptions
    _healthSub = _fusion.healthStream.listen((h) {
      if (!mounted) return;
      setState(() {
        _emaSigma = h.emaSigmaGps;
        _lastDt = h.lastDtSec;
        _gpsAcc = h.gpsAccepted;
        _gpsRej = h.gpsRejected;
        _hdgAcc = h.hdgAccepted;
        _hdgRej = h.hdgRejected;
      });
    });

    _rttSub = _transport.rttStream.listen((ms) {
      if (!mounted) return;
      setState(() => _lastRttMs = ms);
    });

    _loadInitialWsUrl();
  }

  Future<void> _loadInitialWsUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kWsUrlPrefKey);
    if (saved != null && saved.isNotEmpty) {
      setState(() => _wsUrl = saved);
      return;
    }
    final envUrl = dotenv.env['WS_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      setState(() => _wsUrl = envUrl);
    }
  }

  @override
  void dispose() {
    _rawSub?.cancel();
    _fusedSub?.cancel();
    _wsConnSub?.cancel();
    _healthSub?.cancel();
    _rttSub?.cancel();
    _fusion.dispose();
    _sensors.dispose();
    _transport.closeAndStopRetry();
    _log.close();
    super.dispose();
  }

  Future<void> _toggleStartStop() async {
    if (_running) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    if (_wsUrl.trim().isEmpty) {
      await _editWsUrl();
      if (_wsUrl.trim().isEmpty) return;
    }

    await _log.open();

    _rawSub = _sensors.stream.listen((s) {
      _log.logRaw(RawSample(
        t: s.timestamp,
        lat: s.lat,
        lon: s.lon,
        heading: s.headingRad * 180.0 / math.pi,
        acc: s.accuracyM,
      ));
    });

    _fusedSub = _fusion.stream.listen((o) {
      final headingDegForLog = o.headingRad * 180.0 / math.pi;

      _log.logFiltered(FilteredSample(
        t: o.t,
        lat: o.lat,
        lon: o.lon,
        heading: headingDegForLog,
      ));

      _transport.sendFusionSample(
        lat: o.lat,
        lon: o.lon,
        headingDeg: headingDegForLog,
        timestamp: o.t,
        accuracyM: o.accuracyM,
      );

      if (mounted) setState(() => _queueLen = _transport.queueLength);
    });

    _transport.connectWithRetry(_wsUrl);

    await _fusion.start(gpsDistanceFilterM: _gpsDistanceFilterM);
    if (mounted) setState(() => _running = true);
  }

  Future<void> _stop() async {
    await _fusion.stop();
    await _rawSub?.cancel();
    await _fusedSub?.cancel();
    await _transport.closeAndStopRetry();
    await _log.close();
    if (mounted) setState(() => _running = false);
  }

  Future<void> _editWsUrl() async {
    final ctrl = TextEditingController(text: _wsUrl);
    final newUrl = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit WebSocket URL'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'ws://host:port',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          autofillHints: const [AutofillHints.url],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    if (newUrl != null && newUrl.isNotEmpty) {
      setState(() => _wsUrl = newUrl);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kWsUrlPrefKey, _wsUrl);

      if (_running) {
        await _transport.closeAndStopRetry();
        _transport.connectWithRetry(_wsUrl);
      }
    }
  }

  void _openLogs() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => LogScreen(logService: _log)));
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initial: FilteringParams(
            gpsDistanceFilterM: _gpsDistanceFilterM,
            rGpsPosM: _fusion.rGpsPosM,
            rHeadingDeg: _fusion.rHeadingDeg,
            qPosDrift: _fusion.qPosDrift,
            qHeadingDrift: _fusion.qHeadingDrift,
            gpsSigmaScaleK: _fusion.gpsSigmaScaleK,
            gateGps: _fusion.gateGps,
            gateHeading: _fusion.gateHeading,
            headingOffsetDeg: _fusion.headingOffsetDeg,
            headingAlpha: _sensors.headingSmoothingAlpha,
            maxDtSec: _fusion.clampDtMaxSec,
          ),
          onApply: (p) async {
            _fusion.setAdvancedParams(
              rGpsPosM: p.rGpsPosM,
              rHeadingDeg: p.rHeadingDeg,
              qPosDrift: p.qPosDrift,
              qHeadingDrift: p.qHeadingDrift,
            );
            _fusion.setAdaptiveGpsK(p.gpsSigmaScaleK);
            _fusion.setGates(gateGps: p.gateGps, gateHeading: p.gateHeading);
            _fusion.setHeadingOffsetDeg(p.headingOffsetDeg);
            _sensors.setHeadingSmoothingAlpha(p.headingAlpha);
            _fusion.setClampDtMax(p.maxDtSec);
            _gpsDistanceFilterM = p.gpsDistanceFilterM;

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Parameter disimpan')),
              );
            }
          },
        ),
      ),
    );
  }

  void _openMap() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen(logService: _log)));
  }

  // ================= Helper warna & indikator =================
  Color _sevColor(num? v, List<num> th) {
    if (v == null) return Colors.grey;
    if (v <= th[0]) return Colors.green;
    if (v <= th[1]) return Colors.orange;
    return Colors.red;
  }

  Color _ratioColor(int acc, int rej) {
    final tot = acc + rej;
    if (tot < 10) return Colors.grey;
    final r = rej / tot;
    if (r <= 0.20) return Colors.green;
    if (r <= 0.40) return Colors.orange;
    return Colors.red;
  }

  Widget _indicatorBox({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _queueLen = _transport.queueLength;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: _wsConnected ? Colors.green[50] : Colors.red[50],
                child: ListTile(
                  leading: Icon(_wsConnected ? Icons.check_circle : Icons.wifi_off,
                      color: _wsConnected ? Colors.green : Colors.red, size: 30),
                  title: Text(
                    _wsConnected ? 'Connected' : 'Disconnected',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _wsConnected ? Colors.green[800] : Colors.red[800],
                    ),
                  ),
                  subtitle: Text(_wsUrl, style: const TextStyle(fontSize: 13)),
                  trailing: IconButton(icon: const Icon(Icons.edit), onPressed: _editWsUrl),
                ),
              ),
              const SizedBox(height: 12),

              // ------- LIVE HUD -------
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Live HUD',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              foregroundColor: Colors.indigo,
                            ),
                            onPressed: () {
                              _fusion.resetHealth();
                              // Sinkronkan UI segera
                              setState(() {
                                _gpsAcc = _gpsRej = _hdgAcc = _hdgRej = 0;
                              });
                            },
                            icon: const Icon(Icons.restart_alt, size: 18),
                            label: const Text('Reset'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isThreeCol = constraints.maxWidth >= 380;
                          final crossCount = isThreeCol ? 3 : 2;
                          const gap = 8.0;
                          final aspect = isThreeCol ? 2.8 : 2.3;

                          final rttColor   = _sevColor(_lastRttMs, [150, 300]);
                          final qColor     = _sevColor(_queueLen, [0, 20]);
                          final sigmaColor = _sevColor(_emaSigma, [4, 8]);
                          final dtColor    = _sevColor(_lastDt, [0.30, 0.60]);
                          final gpsColor   = _ratioColor(_gpsAcc, _gpsRej);
                          final hdgColor   = _ratioColor(_hdgAcc, _hdgRej);

                          final items = <Widget>[
                            _indicatorBox(title: 'RTT',
                              value: _lastRttMs != null ? '${_lastRttMs!.toStringAsFixed(0)} ms' : '—',
                              color: rttColor),
                            _indicatorBox(title: 'WS Queue', value: '$_queueLen', color: qColor),
                            _indicatorBox(title: 'σ_GPS (EMA)', value: '${_emaSigma.toStringAsFixed(1)} m', color: sigmaColor),
                            _indicatorBox(title: 'dt', value: '${_lastDt.toStringAsFixed(3)} s', color: dtColor),
                            _indicatorBox(title: 'GPS acc/rej', value: '$_gpsAcc / $_gpsRej', color: gpsColor),
                            _indicatorBox(title: 'HDG acc/rej', value: '$_hdgAcc / $_hdgRej', color: hdgColor),
                          ];

                          return GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossCount,
                              crossAxisSpacing: gap,
                              mainAxisSpacing: gap,
                              childAspectRatio: aspect,
                            ),
                            itemCount: items.length,
                            itemBuilder: (_, i) => items[i],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              FilledButton.icon(
                onPressed: _toggleStartStop,
                icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                label: Text(_running ? 'STOP FILTERING' : 'START FILTERING'),
                style: FilledButton.styleFrom(
                  backgroundColor: _running ? Colors.red : theme.colorScheme.primary,
                  minimumSize: const Size(double.infinity, 54),
                ),
              ),
              const SizedBox(height: 12),

              FilledButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.tune),
                label: const Text('SETTINGS'),
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 54)),
              ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: _openLogs,
                icon: const Icon(Icons.list_alt),
                label: const Text('BUKA LOG'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 54)),
              ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: _openMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('BUKA PETA (LOG)'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 54)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
