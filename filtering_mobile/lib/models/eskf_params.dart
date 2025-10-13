class EskfParams {
  // Model
  final bool useConstantVelocity;

  // P0 (kovariansi awal)
  final double P0_pos_m2;
  final double P0_vel_mps2; // dipakai jika CV
  final double P0_yaw_rad2;

  // Q (per detik)
  final double Q_pos_m2ps;     // untuk CP (atau turunan dari vel pada CV)
  final double Q_vel_mps2ps;   // untuk CV
  final double Q_yaw_rad2ps;

  // R
  final double R_gps_pos_m2;       // variansi posisi GPS (m^2)
  final double R_compass_yaw_rad2; // variansi heading kompas (rad^2)

  // Gating / kualitas data
  final double gpsAccuracyMax_m;   // drop jika akurasi > ambang
  final double gpsJumpGate_m;      // drop jika loncatan dari prediksi > ambang
  final double compassGate_deg;    // drop jika deviasi heading > ambang

  // Adaptif noise
  final bool adaptiveRgps;
  final double adaptiveRgpsK;       // R = k * (accuracy_m)^2

  // Timing
  final double dtMin_s;
  final double sendRateHz;

  // ENU origin (opsional)
  final double? lat0Deg;
  final double? lon0Deg;

  // Future IMU (opsional)
  final bool useGyro;
  final double R_gyro_radps2;
  final double Q_biasGyro_rad2ps3;

  const EskfParams({
    this.useConstantVelocity = true,
    this.P0_pos_m2 = 25.0,
    this.P0_vel_mps2 = 1.0,
    this.P0_yaw_rad2 = 0.0305, // (10°)^2
    this.Q_pos_m2ps = 0.1,
    this.Q_vel_mps2ps = 0.5,
    this.Q_yaw_rad2ps = 0.0076, // (5°)^2 per detik
    this.R_gps_pos_m2 = 25.0,   // (≈ 5 m)^2
    this.R_compass_yaw_rad2 = 0.0195, // (8°)^2
    this.gpsAccuracyMax_m = 20.0,
    this.gpsJumpGate_m = 40.0,
    this.compassGate_deg = 40.0,
    this.adaptiveRgps = true,
    this.adaptiveRgpsK = 2.0,
    this.dtMin_s = 0.05,
    this.sendRateHz = 5.0,
    this.lat0Deg,
    this.lon0Deg,
    this.useGyro = false,
    this.R_gyro_radps2 = 0.001,
    this.Q_biasGyro_rad2ps3 = 1e-6,
  });

  EskfParams copyWith({
    bool? useConstantVelocity,
    double? P0_pos_m2,
    double? P0_vel_mps2,
    double? P0_yaw_rad2,
    double? Q_pos_m2ps,
    double? Q_vel_mps2ps,
    double? Q_yaw_rad2ps,
    double? R_gps_pos_m2,
    double? R_compass_yaw_rad2,
    double? gpsAccuracyMax_m,
    double? gpsJumpGate_m,
    double? compassGate_deg,
    bool? adaptiveRgps,
    double? adaptiveRgpsK,
    double? dtMin_s,
    double? sendRateHz,
    double? lat0Deg,
    double? lon0Deg,
    bool? useGyro,
    double? R_gyro_radps2,
    double? Q_biasGyro_rad2ps3,
  }) {
    return EskfParams(
      useConstantVelocity: useConstantVelocity ?? this.useConstantVelocity,
      P0_pos_m2: P0_pos_m2 ?? this.P0_pos_m2,
      P0_vel_mps2: P0_vel_mps2 ?? this.P0_vel_mps2,
      P0_yaw_rad2: P0_yaw_rad2 ?? this.P0_yaw_rad2,
      Q_pos_m2ps: Q_pos_m2ps ?? this.Q_pos_m2ps,
      Q_vel_mps2ps: Q_vel_mps2ps ?? this.Q_vel_mps2ps,
      Q_yaw_rad2ps: Q_yaw_rad2ps ?? this.Q_yaw_rad2ps,
      R_gps_pos_m2: R_gps_pos_m2 ?? this.R_gps_pos_m2,
      R_compass_yaw_rad2: R_compass_yaw_rad2 ?? this.R_compass_yaw_rad2,
      gpsAccuracyMax_m: gpsAccuracyMax_m ?? this.gpsAccuracyMax_m,
      gpsJumpGate_m: gpsJumpGate_m ?? this.gpsJumpGate_m,
      compassGate_deg: compassGate_deg ?? this.compassGate_deg,
      adaptiveRgps: adaptiveRgps ?? this.adaptiveRgps,
      adaptiveRgpsK: adaptiveRgpsK ?? this.adaptiveRgpsK,
      dtMin_s: dtMin_s ?? this.dtMin_s,
      sendRateHz: sendRateHz ?? this.sendRateHz,
      lat0Deg: lat0Deg ?? this.lat0Deg,
      lon0Deg: lon0Deg ?? this.lon0Deg,
      useGyro: useGyro ?? this.useGyro,
      R_gyro_radps2: R_gyro_radps2 ?? this.R_gyro_radps2,
      Q_biasGyro_rad2ps3: Q_biasGyro_rad2ps3 ?? this.Q_biasGyro_rad2ps3,
    );
  }
}
