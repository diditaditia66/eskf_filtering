// lib/services/sensors_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';

class GpsCompassSample {
  final double lat;
  final double lon;
  final double? accuracyM;
  final double headingRad; // rad (-pi..pi)
  final DateTime timestamp;
  GpsCompassSample({
    required this.lat,
    required this.lon,
    required this.headingRad,
    this.accuracyM,
    required this.timestamp,
  });
}

class SensorsService {
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<CompassEvent>? _compassSub;
  Timer? _tick;

  // cache nilai terakhir dari sensor
  Position? _lastPos;
  double _lastHeadingRad = 0.0;

  final _out = StreamController<GpsCompassSample>.broadcast();
  Stream<GpsCompassSample> get stream => _out.stream;

  /// Pastikan izin lokasi diberikan
  Future<bool> ensurePermissions() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  /// Mulai baca sensor. `sampleEvery` = periode emisi output (default 1 detik).
  Future<void> start({
    int gpsDistanceFilterM = 0,
    Duration sampleEvery = const Duration(seconds: 1),
  }) async {
    // --- Kompas (biasanya cepat) ---
    _compassSub = FlutterCompass.events?.listen((event) {
      final deg = (event.heading ?? 0.0).toDouble();
      _lastHeadingRad = deg * 3.141592653589793 / 180.0;
    });

    // --- GPS stream (ambil secepat mungkin; kita throttle di luar) ---
    // Untuk Android, kita coba set intervalDuration ~ 500ms agar cepat namun efisien.
    final base = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: gpsDistanceFilterM, // 0 = semua pergerakan
    );

    LocationSettings settings = base;
    try {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: gpsDistanceFilterM,
        intervalDuration: const Duration(milliseconds: 500),
        forceLocationManager: false,
      );
    } catch (_) {
      // jika bukan AndroidSettings, pakai base apa adanya
      settings = base;
    }

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      _lastPos = pos; // simpan terakhir
    });

    // --- Throttle output setiap 1 detik ---
    _tick?.cancel();
    _tick = Timer.periodic(sampleEvery, (_) {
      final p = _lastPos;
      if (p == null) return; // belum ada fix

      _out.add(GpsCompassSample(
        lat: p.latitude,
        lon: p.longitude,
        headingRad: _lastHeadingRad,
        accuracyM: p.accuracy,
        timestamp: DateTime.now(),
      ));
    });
  }

  /// Hentikan semua
  Future<void> stop() async {
    await _gpsSub?.cancel();
    await _compassSub?.cancel();
    _tick?.cancel();
    _gpsSub = null;
    _compassSub = null;
    _tick = null;
    // Jangan tutup _out, supaya bisa start lagi. Tutupnya di dispose() saja.
  }

  Future<void> dispose() async {
    await stop();
    await _out.close();
  }
}
