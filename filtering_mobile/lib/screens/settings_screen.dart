// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';

enum FilterMode {
  openArea,
  betweenBuildings,
  underTrees,
  magneticDisturbance,
  fastMovement,
}

class FilteringParams {
  final int gpsDistanceFilterM;
  final double rGpsPosM;
  final double rHeadingDeg;
  final double qPosDrift;
  final double qHeadingDrift;
  final double gpsSigmaScaleK;
  final double gateGps;
  final double gateHeading;
  final double headingOffsetDeg;
  final FilterMode? presetMode; // ⬅️ Tambahan baru

  const FilteringParams({
    required this.gpsDistanceFilterM,
    required this.rGpsPosM,
    required this.rHeadingDeg,
    required this.qPosDrift,
    required this.qHeadingDrift,
    required this.gpsSigmaScaleK,
    required this.gateGps,
    required this.gateHeading,
    required this.headingOffsetDeg,
    this.presetMode,
  });

  FilteringParams copyWith({
    int? gpsDistanceFilterM,
    double? rGpsPosM,
    double? rHeadingDeg,
    double? qPosDrift,
    double? qHeadingDrift,
    double? gpsSigmaScaleK,
    double? gateGps,
    double? gateHeading,
    double? headingOffsetDeg,
    FilterMode? presetMode,
  }) {
    return FilteringParams(
      gpsDistanceFilterM: gpsDistanceFilterM ?? this.gpsDistanceFilterM,
      rGpsPosM: rGpsPosM ?? this.rGpsPosM,
      rHeadingDeg: rHeadingDeg ?? this.rHeadingDeg,
      qPosDrift: qPosDrift ?? this.qPosDrift,
      qHeadingDrift: qHeadingDrift ?? this.qHeadingDrift,
      gpsSigmaScaleK: gpsSigmaScaleK ?? this.gpsSigmaScaleK,
      gateGps: gateGps ?? this.gateGps,
      gateHeading: gateHeading ?? this.gateHeading,
      headingOffsetDeg: headingOffsetDeg ?? this.headingOffsetDeg,
      presetMode: presetMode ?? this.presetMode,
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final FilteringParams initial;
  final void Function(FilteringParams) onApply;

  const SettingsScreen({
    super.key,
    required this.initial,
    required this.onApply,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _gpsFilter;
  late double _rGpsPosM;
  late double _rHeadingDeg;
  late double _qPosDrift;
  late double _qHeadingDrift;
  late double _gpsSigmaScaleK;
  late double _gateGps;
  late double _gateHeading;
  late double _headingOffsetDeg;
  FilterMode? _selectedMode;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _gpsFilter = p.gpsDistanceFilterM;
    _rGpsPosM = p.rGpsPosM;
    _rHeadingDeg = p.rHeadingDeg;
    _qPosDrift = p.qPosDrift;
    _qHeadingDrift = p.qHeadingDrift;
    _gpsSigmaScaleK = p.gpsSigmaScaleK;
    _gateGps = p.gateGps;
    _gateHeading = p.gateHeading;
    _headingOffsetDeg = p.headingOffsetDeg;
    _selectedMode = p.presetMode; // ⬅️ Restore preset saat dibuka kembali
  }

  void _applyPreset(FilterMode mode) {
    setState(() {
      _selectedMode = mode;
      switch (mode) {
        case FilterMode.openArea:
          _rGpsPosM = 3.5;
          _rHeadingDeg = 4.5;
          _qPosDrift = 0.2;
          _qHeadingDrift = 0.001;
          _gateGps = 3.5;
          _gateHeading = 3.0;
          _gpsSigmaScaleK = 0.5;
          break;

        case FilterMode.betweenBuildings:
          _rGpsPosM = 7.0;
          _rHeadingDeg = 6.5;
          _qPosDrift = 0.1;
          _qHeadingDrift = 0.0008;
          _gateGps = 3.0;
          _gateHeading = 2.5;
          _gpsSigmaScaleK = 0.7;
          break;

        case FilterMode.underTrees:
          _rGpsPosM = 6.5;
          _rHeadingDeg = 5.0;
          _qPosDrift = 0.1;
          _qHeadingDrift = 0.0008;
          _gateGps = 3.0;
          _gateHeading = 2.8;
          _gpsSigmaScaleK = 0.6;
          break;

        case FilterMode.magneticDisturbance:
          _rGpsPosM = 3.5;
          _rHeadingDeg = 10.0;
          _qPosDrift = 0.2;
          _qHeadingDrift = 0.002;
          _gateGps = 3.5;
          _gateHeading = 5.0;
          _gpsSigmaScaleK = 0.5;
          break;

        case FilterMode.fastMovement:
          _rGpsPosM = 2.5;
          _rHeadingDeg = 4.0;
          _qPosDrift = 0.5;
          _qHeadingDrift = 0.002;
          _gateGps = 4.0;
          _gateHeading = 3.5;
          _gpsSigmaScaleK = 0.4;
          break;
      }
    });
  }

  void _apply() {
    widget.onApply(
      FilteringParams(
        gpsDistanceFilterM: _gpsFilter,
        rGpsPosM: _rGpsPosM,
        rHeadingDeg: _rHeadingDeg,
        qPosDrift: _qPosDrift,
        qHeadingDrift: _qHeadingDrift,
        gpsSigmaScaleK: _gpsSigmaScaleK,
        gateGps: _gateGps,
        gateHeading: _gateHeading,
        headingOffsetDeg: _headingOffsetDeg,
        presetMode: _selectedMode, // ⬅️ simpan preset yang sedang aktif
      ),
    );
    Navigator.pop(context);
  }

  Widget _dropdownPreset() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Preset Mode Kampus',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            DropdownButtonFormField<FilterMode?>(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              value: _selectedMode,
              hint: const Text('Pilih mode kampus...'),
              items: const [
                DropdownMenuItem(
                  value: null,
                  child: Text('❌ Tanpa Preset (Manual)'),
                ),
                DropdownMenuItem(
                  value: FilterMode.openArea,
                  child: Text('🟢 Lapangan Terbuka'),
                ),
                DropdownMenuItem(
                  value: FilterMode.betweenBuildings,
                  child: Text('🏢 Antar Gedung'),
                ),
                DropdownMenuItem(
                  value: FilterMode.underTrees,
                  child: Text('🌳 Area Rindang (Bawah Pohon)'),
                ),
                DropdownMenuItem(
                  value: FilterMode.magneticDisturbance,
                  child: Text('🧲 Gangguan Magnetik'),
                ),
                DropdownMenuItem(
                  value: FilterMode.fastMovement,
                  child: Text('🚗 Pergerakan Cepat'),
                ),
              ],
              onChanged: (mode) {
                setState(() => _selectedMode = mode);
                if (mode != null) _applyPreset(mode);
              },
            ),
            const SizedBox(height: 6),
            Text(
              _selectedMode == null
                  ? 'Mode manual aktif — parameter dapat disesuaikan bebas.'
                  : 'Preset aktif: parameter otomatis menyesuaikan kondisi.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),
            Text(
              'Preset terakhir yang dipilih akan tersimpan otomatis.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- SLIDER UI ----------------
  Widget _sliderWithSteppers({
    required String title,
    required String unitLabel,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
    int? divisions,
    String Function(double)? toLabel,
  }) {
    String showLabel(double v) =>
        toLabel != null ? toLabel(v) : '${v.toStringAsFixed(2)}$unitLabel';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              onPressed: () {
                final nv = (value - step).clamp(min, max).toDouble();
                onChanged(nv);
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: showLabel(value),
                onChanged: onChanged,
              ),
            ),
            IconButton(
              onPressed: () {
                final nv = (value + step).clamp(min, max).toDouble();
                onChanged(nv);
              },
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 6),
            Text(showLabel(value)),
          ],
        ),
      ],
    );
  }

  Widget _intSliderWithSteppers({
    required String title,
    required String unitLabel,
    required int value,
    required int min,
    required int max,
    required int step,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              onPressed: () {
                final nv = (value - step).clamp(min, max);
                onChanged(nv);
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Slider(
                value: value.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: (max - min) ~/ step,
                label: '$value$unitLabel',
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
            IconButton(
              onPressed: () {
                final nv = (value + step).clamp(min, max);
                onChanged(nv);
              },
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 6),
            Text('$value$unitLabel'),
          ],
        ),
      ],
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parameter ESKF')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _dropdownPreset(),
            _sectionCard('Sensor', [
              _intSliderWithSteppers(
                title: 'GPS Distance Filter',
                unitLabel: ' m',
                value: _gpsFilter,
                min: 1,
                max: 10,
                step: 1,
                onChanged: (v) => setState(() => _gpsFilter = v),
              ),
            ]),
            _sectionCard('Model & Noise', [
              _sliderWithSteppers(
                title: 'R GPS Pos (σ) [m]',
                unitLabel: ' m',
                value: _rGpsPosM,
                min: 0.5,
                max: 10.0,
                step: 0.1,
                divisions: 95,
                onChanged: (v) => setState(() => _rGpsPosM = v),
              ),
              _sliderWithSteppers(
                title: 'R Heading (σ) [deg]',
                unitLabel: '°',
                value: _rHeadingDeg,
                min: 1.0,
                max: 15.0,
                step: 0.5,
                divisions: 28,
                onChanged: (v) => setState(() => _rHeadingDeg = v),
              ),
              _sliderWithSteppers(
                title: 'Q Pos Drift',
                unitLabel: '',
                value: _qPosDrift,
                min: 0.0,
                max: 5.0,
                step: 0.1,
                divisions: 50,
                onChanged: (v) => setState(() => _qPosDrift = v),
              ),
              _sliderWithSteppers(
                title: 'Q Heading Drift',
                unitLabel: '',
                value: _qHeadingDrift,
                min: 0.0,
                max: 0.1,
                step: 0.005,
                divisions: 20,
                onChanged: (v) => setState(() => _qHeadingDrift = v),
              ),
            ]),
            _sectionCard('Adaptasi & Gate', [
              _sliderWithSteppers(
                title: 'GPS σ scale k (accuracy → σ)',
                unitLabel: '',
                value: _gpsSigmaScaleK,
                min: 0.2,
                max: 1.0,
                step: 0.05,
                divisions: 16,
                onChanged: (v) => setState(() => _gpsSigmaScaleK = v),
              ),
              _sliderWithSteppers(
                title: 'Gate GPS (σ)',
                unitLabel: '',
                value: _gateGps,
                min: 2.5,
                max: 6.0,
                step: 0.25,
                divisions: 14,
                onChanged: (v) => setState(() => _gateGps = v),
              ),
              _sliderWithSteppers(
                title: 'Gate Heading (σ)',
                unitLabel: '',
                value: _gateHeading,
                min: 2.0,
                max: 5.0,
                step: 0.25,
                divisions: 12,
                onChanged: (v) => setState(() => _gateHeading = v),
              ),
            ]),
            _sectionCard('Kalibrasi', [
              _sliderWithSteppers(
                title: 'Heading Offset (°)',
                unitLabel: '°',
                value: _headingOffsetDeg,
                min: -15.0,
                max: 15.0,
                step: 0.5,
                divisions: 60,
                onChanged: (v) => setState(() => _headingOffsetDeg = v),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.check),
                label: const Text('SIMPAN PERUBAHAN'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
