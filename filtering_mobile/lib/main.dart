import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/sensors_service.dart';
import 'services/fusion_service.dart';
import 'services/transport_service.dart';
import 'services/log_service.dart';

import 'screens/log_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/map_screen.dart'; // Map dari log (tanpa FMTC)

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env"); // baca token Mapbox dari .env
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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

  bool _running = false;
  bool _wsConnected = false;
  String _last = '-';
  int _gpsDistanceFilterM = 1;

  double _toCompass360(double rad) {
    final deg = rad * 180.0 / math.pi;
    return (deg % 360 + 360) % 360;
  }

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
  }

  @override
  void dispose() {
    _rawSub?.cancel();
    _fusedSub?.cancel();
    _wsConnSub?.cancel();
    _fusion.dispose();
    _sensors.dispose();
    _transport.close();
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
      final headingDegForUi = _toCompass360(o.headingRad);
      final headingDegForLog = o.headingRad * 180.0 / math.pi;

      _log.logFiltered(FilteredSample(
        t: o.t,
        lat: o.lat,
        lon: o.lon,
        heading: headingDegForLog,
      ));

      if (_transport.isConnected) {
        _transport.sendFusionSample(
          lat: o.lat,
          lon: o.lon,
          headingDeg: headingDegForLog,
          timestamp: o.t,
        );
      }

      if (mounted) {
        setState(() {
          _last =
              'lat=${o.lat.toStringAsFixed(6)}, lon=${o.lon.toStringAsFixed(6)}, hdg=${headingDegForUi.toStringAsFixed(1)}°';
        });
      }
    });

    try {
      await _transport.connect(_wsUrl);
    } catch (_) {}

    await _fusion.start(gpsDistanceFilterM: _gpsDistanceFilterM);
    if (mounted) setState(() => _running = true);
  }

  Future<void> _stop() async {
    await _fusion.stop();
    await _rawSub?.cancel();
    await _fusedSub?.cancel();
    await _transport.close();
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
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    if (newUrl != null && newUrl.isNotEmpty) {
      setState(() => _wsUrl = newUrl);
      if (_running) {
        await _transport.close();
        try {
          await _transport.connect(_wsUrl);
        } catch (_) {}
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

  // Map: tampilkan perbandingan log Raw & Filtered (statis dari log)
  void _openMap() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen(logService: _log)));
  }

  Future<void> _confirmClearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus semua log?'),
        content: const Text('Tindakan ini akan menghapus seluruh data log yang tersimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _log.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semua log berhasil dihapus')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              const SizedBox(height: 12),

              FilledButton.icon(
                onPressed: _confirmClearLogs,
                icon: const Icon(Icons.delete_forever),
                label: const Text('CLEAR LOGS'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size(double.infinity, 54),
                ),
              ),
              const SizedBox(height: 24),

              Card(
                child: ListTile(
                  leading: const Icon(Icons.navigation_outlined),
                  title: const Text('Output Terakhir'),
                  subtitle: Text(_last, style: const TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
