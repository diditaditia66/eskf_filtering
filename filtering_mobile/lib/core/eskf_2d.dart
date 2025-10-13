// lib/core/eskf_2d.dart
import 'dart:math' as m;

class ESKF2D {
  // State
  final List<double> _x = List.filled(5, 0.0); // x,y,vx,vy,psi
  // Covariance (5x5)
  final List<List<double>> _P = List.generate(5, (_) => List.filled(5, 0.0));

  // Params (bisa diubah runtime)
  double rGpsPosM;     // sigma GPS [m]
  double rHeadingRad;  // sigma heading [rad]
  double qPosDrift;    // intensitas RW vel [m^2/s^3]
  double qHeading;     // intensitas RW yaw [rad^2/s]

  // Gate terpisah (σ)
  double gateGps;
  double gateHeading;

  bool _initialized = false;
  double _lastT = 0.0; // detik

  ESKF2D({
    required this.rGpsPosM,
    required this.rHeadingRad,
    required this.qPosDrift,
    required this.qHeading,
    required this.gateGps,
    required this.gateHeading,
  });

  /// Reset full state/cov
  void reset() {
    for (int i = 0; i < 5; i++) {
      _x[i] = 0.0;
      for (int j = 0; j < 5; j++) {
        _P[i][j] = (i == j) ? 1e2 : 0.0;
      }
    }
    _initialized = false;
    _lastT = 0.0;
  }

  void _initFrom(double x, double y, double psi, double tSec) {
    _x[0] = x;
    _x[1] = y;
    _x[2] = 0.0;
    _x[3] = 0.0;
    _x[4] = _wrap(psi);

    for (int i = 0; i < 5; i++) {
      for (int j = 0; j < 5; j++) {
        _P[i][j] = 0.0;
      }
    }
    _P[0][0] = 25.0;
    _P[1][1] = 25.0;
    _P[2][2] = 4.0;
    _P[3][3] = 4.0;
    _P[4][4] = (m.pi / 6) * (m.pi / 6);

    _initialized = true;
    _lastT = tSec;
  }

  void predict(double tSec) {
    if (!_initialized) return;
    double dt = tSec - _lastT;
    if (dt <= 0) dt = 1e-3;
    _lastT = tSec;

    final F = [
      [1.0, 0.0, dt, 0.0, 0.0],
      [0.0, 1.0, 0.0, dt, 0.0],
      [0.0, 0.0, 1.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 1.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 1.0],
    ];

    final xn = List<double>.from(_x);
    xn[0] = _x[0] + _x[2] * dt;
    xn[1] = _x[1] + _x[3] * dt;
    xn[2] = _x[2];
    xn[3] = _x[3];
    xn[4] = _wrap(_x[4]);
    for (int i = 0; i < 5; i++) _x[i] = xn[i];

    final double qv = qPosDrift;
    final double qpsi = qHeading;
    final double dt2 = dt * dt;
    final double dt3 = dt2 * dt;

    final double Qpp = (dt3 / 3.0) * qv;
    final double Qpv = (dt2 / 2.0) * qv;
    final double Qvv = dt * qv;

    final Q = [
      [Qpp, 0.0, Qpv, 0.0, 0.0],
      [0.0, Qpp, 0.0, Qpv, 0.0],
      [Qpv, 0.0, Qvv, 0.0, 0.0],
      [0.0, Qpv, 0.0, Qvv, 0.0],
      [0.0, 0.0, 0.0, 0.0, dt * qpsi],
    ];

    final FP = _mul(F, _P);
    final FPFt = _mul(FP, _transpose(F));
    final Pn = _add(FPFt, Q);
    _copyTo(Pn, _P);
  }

  void updateGps(double zgx, double zgy) {
    if (!_initialized) {
      _initFrom(zgx, zgy, _x[4], _lastT);
    }
    final H = [
      [1.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0, 0.0],
    ];
    final z = [[zgx], [zgy]];
    final h = [[_x[0]], [_x[1]]];
    final R = [
      [rGpsPosM * rGpsPosM, 0.0],
      [0.0, rGpsPosM * rGpsPosM],
    ];
    _update(z, h, H, R, doGate: true, gateOverride: gateGps);
  }

  void updateHeading(double psiRad) {
    if (!_initialized) {
      _x[4] = _wrap(psiRad);
      _initialized = true;
    }
    final H = [
      [0.0, 0.0, 0.0, 0.0, 1.0],
    ];
    final z = [[_wrap(psiRad)]];
    final h = [[_wrap(_x[4])]];
    final R = [
      [rHeadingRad * rHeadingRad],
    ];
    _update(z, h, H, R, doGate: true, circularIdx: 0, gateOverride: gateHeading);
  }

  void _update(
    List<List<double>> z,
    List<List<double>> h,
    List<List<double>> H,
    List<List<double>> R, {
    bool doGate = false,
    int? circularIdx,
    double? gateOverride,
  }) {
    var v = _sub(z, h);
    if (circularIdx != null) {
      v[circularIdx][0] = _wrap(v[circularIdx][0]);
    }

    final HP = _mul(H, _P);
    final HPHt = _mul(HP, _transpose(H));
    final S = _add(HPHt, R);

    if (doGate) {
      final Sinv = _inv(S);
      if (Sinv == null) return;
      final vt = _transpose(v);
      final mahal = _mul(_mul(vt, Sinv), v)[0][0];
      final th = gateOverride ?? 3.0;
      if (mahal.isNaN || mahal > th * th) return;
    }

    final Sinv = _inv(S);
    if (Sinv == null) return;

    final PHt = _mul(_P, _transpose(H));
    final K = _mul(PHt, Sinv);
    final Kv = _mul(K, v);
    for (int i = 0; i < 5; i++) {
      _x[i] += Kv[i][0];
    }
    _x[4] = _wrap(_x[4]);

    final I = _eye(5);
    final KH = _mul(K, H);
    final ImKH = _sub(I, KH);
    final ImKH_P = _mul(ImKH, _P);
    final term1 = _mul(ImKH_P, _transpose(ImKH));
    final KR = _mul(K, R);
    final term2 = _mul(KR, _transpose(K));
    final Pn = _add(term1, term2);
    _copyTo(Pn, _P);
  }

  // --- Utils matrix ---
  List<List<double>> _mul(List<List<double>> A, List<List<double>> B) {
    final r = A.length, c = B[0].length, n = A[0].length;
    final X = List.generate(r, (_) => List.filled(c, 0.0));
    for (int i = 0; i < r; i++) {
      for (int k = 0; k < n; k++) {
        final aik = A[i][k];
        for (int j = 0; j < c; j++) {
          X[i][j] += aik * B[k][j];
        }
      }
    }
    return X;
  }

  List<List<double>> _add(List<List<double>> A, List<List<double>> B) {
    final r = A.length, c = A[0].length;
    final X = List.generate(r, (_) => List.filled(c, 0.0));
    for (int i = 0; i < r; i++) {
      for (int j = 0; j < c; j++) X[i][j] = A[i][j] + B[i][j];
    }
    return X;
  }

  List<List<double>> _sub(List<List<double>> A, List<List<double>> B) {
    final r = A.length, c = A[0].length;
    final X = List.generate(r, (_) => List.filled(c, 0.0));
    for (int i = 0; i < r; i++) {
      for (int j = 0; j < c; j++) X[i][j] = A[i][j] - B[i][j];
    }
    return X;
  }

  List<List<double>> _transpose(List<List<double>> A) {
    final r = A.length, c = A[0].length;
    final X = List.generate(c, (_) => List.filled(r, 0.0));
    for (int i = 0; i < r; i++) {
      for (int j = 0; j < c; j++) X[j][i] = A[i][j];
    }
    return X;
  }

  List<List<double>> _eye(int n) {
    final I = List.generate(n, (_) => List.filled(n, 0.0));
    for (int i = 0; i < n; i++) I[i][i] = 1.0;
    return I;
  }

  void _copyTo(List<List<double>> src, List<List<double>> dst) {
    for (int i = 0; i < src.length; i++) {
      for (int j = 0; j < src[0].length; j++) dst[i][j] = src[i][j];
    }
  }

  List<List<double>>? _inv(List<List<double>> A) {
    final n = A.length;
    final M = List.generate(n, (i) => List<double>.from(A[i]));
    final I = _eye(n);
    for (int i = 0; i < n; i++) {
      double pivot = M[i][i].abs();
      int pivrow = i;
      for (int r = i + 1; r < n; r++) {
        final v = M[r][i].abs();
        if (v > pivot) {
          pivot = v;
          pivrow = r;
        }
      }
      if (pivot < 1e-12) return null;
      if (pivrow != i) {
        final tmp = M[i];
        M[i] = M[pivrow];
        M[pivrow] = tmp;
        final tmp2 = I[i];
        I[i] = I[pivrow];
        I[pivrow] = tmp2;
      }
      final piv = M[i][i];
      for (int j = 0; j < n; j++) {
        M[i][j] /= piv;
        I[i][j] /= piv;
      }
      for (int r = 0; r < n; r++) {
        if (r == i) continue;
        final f = M[r][i];
        for (int j = 0; j < n; j++) {
          M[r][j] -= f * M[i][j];
          I[r][j] -= f * I[i][j];
        }
      }
    }
    return I;
  }

  double _wrap(double a) {
    double x = (a + m.pi) % (2 * m.pi);
    if (x < 0) x += 2 * m.pi;
    return x - m.pi;
  }

  double get x => _x[0];
  double get y => _x[1];
  double get vx => _x[2];
  double get vy => _x[3];
  double get psi => _x[4];

  void step({
    required double tSec,
    double? gpsX,
    double? gpsY,
    double? headingRad,
  }) {
    if (!_initialized && gpsX != null && gpsY != null) {
      _initFrom(gpsX, gpsY, headingRad ?? 0.0, tSec);
    } else if (!_initialized) {
      _lastT = tSec;
      return;
    }

    predict(tSec);
    if (gpsX != null && gpsY != null) updateGps(gpsX, gpsY);
    if (headingRad != null) updateHeading(headingRad);
  }
}
