// lib/services/log_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class RawSample {
  final DateTime t;
  final double lat;      // deg
  final double lon;      // deg
  final double? acc;     // m (nullable)
  final double heading;  // deg

  RawSample({
    required this.t,
    required this.lat,
    required this.lon,
    required this.heading,
    this.acc,
  });
}

class FilteredSample {
  final DateTime t;
  final double lat;     // deg
  final double lon;     // deg
  final double heading; // deg

  FilteredSample({
    required this.t,
    required this.lat,
    required this.lon,
    required this.heading,
  });
}

class LogService {
  // ===== CSV I/O =====
  File? _rawFile;   IOSink? _rawSink;
  File? _filtFile;  IOSink? _filtSink;
  File? _joinedFile;IOSink? _joinedSink;

  RawSample? _latestRaw; // untuk joined
  bool _opened = false;
  bool get isOpen => _opened;

  // ===== In-memory ring buffer (agar LogScreen bisa reload histori) =====
  static const int _cap = 500;
  final List<RawSample> _rawBuf = <RawSample>[];
  final List<FilteredSample> _filtBuf = <FilteredSample>[];

  UnmodifiableListView<RawSample> get recentRawBuffer =>
      UnmodifiableListView(_rawBuf);
  UnmodifiableListView<FilteredSample> get recentFilteredBuffer =>
      UnmodifiableListView(_filtBuf);

  // ===== Stream untuk update live ke LogScreen =====
  final _rawRecentCtrl = StreamController<RawSample>.broadcast();
  final _filtRecentCtrl = StreamController<FilteredSample>.broadcast();
  Stream<RawSample> get recentRawStream => _rawRecentCtrl.stream;
  Stream<FilteredSample> get recentFilteredStream => _filtRecentCtrl.stream;

  /// Membuka 3 file CSV dan menulis header. Idempoten.
  Future<void> open() async {
    if (_opened) return;

    final dir = await getApplicationDocumentsDirectory();
    if (!(await dir.exists())) await dir.create(recursive: true);

    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');

    _rawFile    = File('${dir.path}/raw_samples_$ts.csv');
    _filtFile   = File('${dir.path}/filtered_samples_$ts.csv');
    _joinedFile = File('${dir.path}/joined_samples_$ts.csv');

    _rawSink    = _rawFile!.openWrite(mode: FileMode.writeOnlyAppend);
    _filtSink   = _filtFile!.openWrite(mode: FileMode.writeOnlyAppend);
    _joinedSink = _joinedFile!.openWrite(mode: FileMode.writeOnlyAppend);

    _rawSink!.writeln('t_iso,lat_deg,lon_deg,acc_m,heading_deg');
    _filtSink!.writeln('t_iso,lat_deg,lon_deg,heading_deg');
    _joinedSink!.writeln(
      't_iso,raw_lat_deg,raw_lon_deg,raw_acc_m,raw_heading_deg,'
      'filt_lat_deg,filt_lon_deg,filt_heading_deg',
    );

    _opened = true;
  }

  /// Menutup file I/O. StreamController TIDAK ditutup di sini, supaya LogScreen tetap bisa hidup.
  Future<void> close() async {
    try { await _rawSink?.flush(); await _rawSink?.close(); } catch (_) {}
    try { await _filtSink?.flush(); await _filtSink?.close(); } catch (_) {}
    try { await _joinedSink?.flush(); await _joinedSink?.close(); } catch (_) {}

    _rawSink = null; _filtSink = null; _joinedSink = null;
    _opened = false;
  }

  /// Panggil ini sekali saat aplikasi ditutup total.
  Future<void> dispose() async {
    await close();
    await _rawRecentCtrl.close();
    await _filtRecentCtrl.close();
  }

  /// Menghapus seluruh buffer dan isi log dari memori.
  Future<void> clearAll() async {
    _rawBuf.clear();
    _filtBuf.clear();
    _latestRaw = null;
    // kirim event kosong ke stream agar UI reset
    if (!_rawRecentCtrl.isClosed) _rawRecentCtrl.addStream(Stream.empty());
    if (!_filtRecentCtrl.isClosed) _filtRecentCtrl.addStream(Stream.empty());
    await close(); // pastikan file writer ditutup
  }


  // ===== Logging =====
  void logRaw(RawSample s) {
    _latestRaw = s;

    // simpan ke file
    final sink = _rawSink;
    if (sink != null) {
      sink.writeln([
        s.t.toIso8601String(),
        s.lat.toStringAsFixed(8),
        s.lon.toStringAsFixed(8),
        s.acc?.toStringAsFixed(2) ?? '',
        s.heading.toStringAsFixed(2),
      ].join(','));
    }

    // simpan ke buffer
    _rawBuf.insert(0, s);
    if (_rawBuf.length > _cap) _rawBuf.removeRange(_cap, _rawBuf.length);

    // stream ke UI
    if (!_rawRecentCtrl.isClosed) _rawRecentCtrl.add(s);
  }

  void logFiltered(FilteredSample s) {
    // file filtered
    final fs = _filtSink;
    if (fs != null) {
      fs.writeln([
        s.t.toIso8601String(),
        s.lat.toStringAsFixed(8),
        s.lon.toStringAsFixed(8),
        s.heading.toStringAsFixed(2),
      ].join(','));
    }

    // file joined
    final js = _joinedSink;
    if (js != null) {
      final r = _latestRaw;
      js.writeln([
        s.t.toIso8601String(),
        r?.lat.toStringAsFixed(8) ?? '',
        r?.lon.toStringAsFixed(8) ?? '',
        r?.acc?.toStringAsFixed(2) ?? '',
        r?.heading.toStringAsFixed(2) ?? '',
        s.lat.toStringAsFixed(8),
        s.lon.toStringAsFixed(8),
        s.heading.toStringAsFixed(2),
      ].join(','));
    }

    // buffer
    _filtBuf.insert(0, s);
    if (_filtBuf.length > _cap) _filtBuf.removeRange(_cap, _filtBuf.length);

    // stream
    if (!_filtRecentCtrl.isClosed) _filtRecentCtrl.add(s);
  }

  // optional: path getter
  String? get rawPath => _rawFile?.path;
  String? get filteredPath => _filtFile?.path;
  String? get joinedPath => _joinedFile?.path;
}
