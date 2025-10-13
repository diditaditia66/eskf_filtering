// lib/services/fusion_service.dart
import 'dart:async';
import 'dart:math' as m;

import 'sensors_service.dart';
import '../core/geo_utils.dart';
import '../core/eskf_2d.dart';

class FilteredOutput {
  final double lat;
  final double lon;
  final double headingRad;
  final double? accuracyM;
  final DateTime t;

  const FilteredOutput({
    required this.lat,
    required this.lon,
    required this.headingRad,
    required this.t,
    this.accuracyM,
  });
}

class FusionService {
  final SensorsService _sensors;
  StreamSubscription<GpsCompassSample>? _sub;

  LocalFrame? _frame;
  ESKF2D? _eskf;

  double _rGpsPosM = 4.0;
  double _rHeadingDeg = 5.0;
  double _qPosDrift = 0.2;
  double _qHeadingDrift = 1e-3;

  double _gateGps = 3.5;
  double _gateHeading = 3.0;

  double _emaSigmaGps = 4.0;
  final double _emaAlpha = 0.2;
  double _adaptiveK = 0.5;

  double _headingOffsetDeg = 0.0;

  final _out = StreamController<FilteredOutput>.broadcast();
  Stream<FilteredOutput> get stream => _out.stream;

  bool _running = false;

  FusionService({SensorsService? sensors})
      : _sensors = sensors ?? SensorsService();

  void setAdvancedParams({
    double? rGpsPosM,
    double? rHeadingDeg,
    double? qPosDrift,
    double? qHeadingDrift,
  }) {
    if (rGpsPosM != null) _rGpsPosM = rGpsPosM.clamp(0.1, 50.0);
    if (rHeadingDeg != null) _rHeadingDeg = rHeadingDeg.clamp(0.1, 45.0);
    if (qPosDrift != null) _qPosDrift = qPosDrift.clamp(0.0, 10.0);
    if (qHeadingDrift != null) _qHeadingDrift = qHeadingDrift.clamp(0.0, 1.0);

    if (_eskf != null) {
      _eskf!
        ..rGpsPosM = _rGpsPosM
        ..rHeadingRad = _deg2rad(_rHeadingDeg)
        ..qPosDrift = _qPosDrift
        ..qHeading = _qHeadingDrift
        ..gateGps = _gateGps
        ..gateHeading = _gateHeading;
    }
  }

  void setAdaptiveGpsK(double k) => _adaptiveK = k.clamp(0.2, 1.0);
  void setHeadingOffsetDeg(double d) => _headingOffsetDeg = d;

  void setGates({double? gateGps, double? gateHeading}) {
    if (gateGps != null) _gateGps = gateGps.clamp(1.0, 10.0);
    if (gateHeading != null) _gateHeading = gateHeading.clamp(1.0, 10.0);
    if (_eskf != null) {
      _eskf!
        ..gateGps = _gateGps
        ..gateHeading = _gateHeading;
    }
  }

  void resetState() {
    _frame = null;
    _eskf = null;
  }

  Future<void> start({int gpsDistanceFilterM = 1}) async {
    if (_running) return;
    final ok = await _sensors.ensurePermissions();
    if (!ok) throw Exception('Izin lokasi tidak diberikan / GPS off');

    await _sensors.start(gpsDistanceFilterM: gpsDistanceFilterM);
    _sub?.cancel();
    _sub = _sensors.stream.listen(_onSample);
    _running = true;
  }

  Future<void> stop() async {
    if (!_running) return;
    await _sub?.cancel();
    _sub = null;
    await _sensors.stop();
    _running = false;
  }

  Future<void> dispose() async {
    await stop();
    await _out.close();
  }

  void _onSample(GpsCompassSample s) {
    _frame ??= LocalFrame(s.lat, s.lon);
    final headingMag =
        (s.headingRad.isNaN || !s.headingRad.isFinite) ? 0.0 : s.headingRad;
    final headingTrue = headingMag + _deg2rad(_headingOffsetDeg);

    _eskf ??= ESKF2D(
      rGpsPosM: _rGpsPosM,
      rHeadingRad: _deg2rad(_rHeadingDeg),
      qPosDrift: _qPosDrift,
      qHeading: _qHeadingDrift,
      gateGps: _gateGps,
      gateHeading: _gateHeading,
    );

    final enu = _frame!.llToEnu(s.lat, s.lon);
    final xMeas = enu[0];
    final yMeas = enu[1];

    if (s.accuracyM != null && s.accuracyM! > 0) {
      final rawSigma = (s.accuracyM! * _adaptiveK).clamp(0.5, 50.0);
      _emaSigmaGps = _emaAlpha * rawSigma + (1 - _emaAlpha) * _emaSigmaGps;
      _eskf!.rGpsPosM = _emaSigmaGps;
    } else {
      _eskf!.rGpsPosM = _rGpsPosM;
    }

    _eskf!
      ..rHeadingRad = _deg2rad(_rHeadingDeg)
      ..qPosDrift = _qPosDrift
      ..qHeading = _qHeadingDrift
      ..gateGps = _gateGps
      ..gateHeading = _gateHeading;

    final tSec = s.timestamp.millisecondsSinceEpoch / 1000.0;
    _eskf!.step(
      tSec: tSec,
      gpsX: xMeas,
      gpsY: yMeas,
      headingRad: headingTrue,
    );

    final x = _eskf!.x;
    final y = _eskf!.y;
    final yaw = _eskf!.psi;
    final ll = _frame!.enuToLl(x, y);

    if (!_out.isClosed) {
      _out.add(FilteredOutput(
        lat: ll[0],
        lon: ll[1],
        headingRad: yaw,
        t: s.timestamp,
        accuracyM: s.accuracyM,
      ));
    }
  }

  bool get isRunning => _running;
  double get rGpsPosM => _rGpsPosM;
  double get rHeadingDeg => _rHeadingDeg;
  double get qPosDrift => _qPosDrift;
  double get qHeadingDrift => _qHeadingDrift;
  double get gpsSigmaScaleK => _adaptiveK;
  double get gateGps => _gateGps;
  double get gateHeading => _gateHeading;
  double get headingOffsetDeg => _headingOffsetDeg;

  double _deg2rad(double d) => d * m.pi / 180.0;
}
