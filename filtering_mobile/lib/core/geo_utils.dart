// lib/core/geo_utils.dart
library geo_utils;

import 'dart:math' as m;

/// Utilitas geodesi ringan untuk area lokal (≲ 5–10 km).
/// Menggunakan equirectangular approximation relatif terhadap origin (lat0, lon0).
class LocalFrame {
  final double lat0Rad;
  final double lon0Rad;
  final double cosLat0;

  LocalFrame(double lat0Deg, double lon0Deg)
      : lat0Rad = _deg2rad(lat0Deg),
        lon0Rad = _deg2rad(lon0Deg),
        cosLat0 = m.cos(_deg2rad(lat0Deg));

  /// WGS84 (deg) -> ENU (meter). Return: [xEast, yNorth]
  List<double> llToEnu(double latDeg, double lonDeg) {
    const double R = 6371000.0; // radius rata-rata bumi (m)
    final double lat = _deg2rad(latDeg);
    final double lon = _deg2rad(lonDeg);
    final double dLat = lat - lat0Rad;
    final double dLon = lon - lon0Rad;
    final double x = R * dLon * cosLat0;
    final double y = R * dLat;
    return <double>[x, y];
  }

  /// ENU (meter) -> WGS84 (deg). Return: [latDeg, lonDeg]
  List<double> enuToLl(double x, double y) {
    const double R = 6371000.0;
    const double eps = 1e-12; // guard lintang sangat tinggi
    final double cosL = (cosLat0.abs() < eps)
        ? (cosLat0.isNegative ? -eps : eps)
        : cosLat0;

    final double lat = lat0Rad + y / R;
    final double lon = lon0Rad + x / (R * cosL);
    return <double>[_rad2deg(lat), _rad2deg(lon)];
  }
}

/// Normalisasi sudut ke rentang (-pi, pi]
double wrapAngleRad(double a) {
  double x = (a + m.pi) % (2 * m.pi);
  if (x <= 0) x += 2 * m.pi; // <= agar +pi tetap +pi (bukan -pi)
  return x - m.pi;
}

/// --- util privat ---
double _deg2rad(double d) => d * m.pi / 180.0;
double _rad2deg(double r) => r * 180.0 / m.pi;
