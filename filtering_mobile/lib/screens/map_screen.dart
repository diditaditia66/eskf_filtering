import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../services/log_service.dart';

Future<String> _ensureMbtilesOnDisk(String assetPath, String fileName) async {
  final dir = await getApplicationDocumentsDirectory();
  final out = File('${dir.path}/$fileName');
  if (!await out.exists()) {
    final bytes = await rootBundle.load(assetPath);
    await out.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }
  return out.path;
}

class _MbtilesReader {
  final String path;
  late final Database _db;
  bool _isOpen = false;

  String? scheme;                 // 'xyz' | 'tms'
  List<double>? bounds;           // [minLon, minLat, maxLon, maxLat]
  List<double>? center;           // [lon, lat, zoom]
  int? minZoom, maxZoom;

  _MbtilesReader(this.path);

  Future<void> open() async {
    _db = await openDatabase(path, readOnly: true);
    _isOpen = true;
    await _readMetadata();
  }

  Future<void> close() async {
    if (_isOpen) await _db.close();
    _isOpen = false;
  }

  Future<void> _readMetadata() async {
    final meta = <String, String>{};
    try {
      final rows = await _db.query('metadata', columns: ['name', 'value']);
      for (final r in rows) {
        final k = (r['name'] as String?)?.toLowerCase();
        final v = r['value'] as String?;
        if (k != null && v != null) meta[k] = v;
      }
    } catch (_) {}

    scheme  = meta['scheme']?.toLowerCase();
    minZoom = int.tryParse(meta['minzoom'] ?? '');
    maxZoom = int.tryParse(meta['maxzoom'] ?? '');

    if (meta.containsKey('bounds')) {
      final p = meta['bounds']!
          .split(',')
          .map((e) => double.tryParse(e.trim()))
          .toList();
      if (p.length == 4 && p.every((e) => e != null)) {
        bounds = [p[0]!, p[1]!, p[2]!, p[3]!];
      }
    }
    if (meta.containsKey('center')) {
      final p = meta['center']!
          .split(',')
          .map((e) => double.tryParse(e.trim()))
          .toList();
      if (p.length >= 2 && p[0] != null && p[1] != null) {
        final z = (p.length >= 3 && p[2] != null) ? p[2]!.toDouble() : 16.0;
        center = [p[0]!, p[1]!, z];
      }
    }
  }

  Future<Uint8List?> readTileBytes(int z, int x, int yXyz) async {
    int qy = yXyz;
    if ((scheme ?? 'tms') == 'tms') {
      qy = (1 << z) - 1 - yXyz; // XYZ -> TMS
    }
    try {
      final rows = await _db.query(
        'tiles',
        columns: ['tile_data'],
        where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
        whereArgs: [z, x, qy],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final raw = rows.first['tile_data'];
      if (raw is Uint8List) return raw;
      if (raw is List<int>) return Uint8List.fromList(raw);
    } catch (_) {}
    return null;
  }
}

class _BytesImageProvider extends ImageProvider<_BytesImageProvider> {
  final Future<Uint8List?> Function() loader;
  const _BytesImageProvider(this.loader);

  @override
  Future<_BytesImageProvider> obtainKey(ImageConfiguration configuration) async => this;

  @override
  ImageStreamCompleter loadImage(_BytesImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_load());
  }

  Future<ImageInfo> _load() async {
    final bytes = await loader();
    final fallback = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48,
      0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00,
      0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78,
      0x9C, 0x63, 0x60, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ]);
    final data = bytes ?? fallback;

    final ib = await ui.ImmutableBuffer.fromUint8List(data);
    final desc = await ui.ImageDescriptor.encoded(ib);
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }
}

class _MbtilesTileProvider extends TileProvider {
  final _MbtilesReader reader;
  _MbtilesTileProvider(this.reader);

  @override
  ImageProvider getImage(TileCoordinates c, TileLayer options) {
    return _BytesImageProvider(() => reader.readTileBytes(c.z, c.x, c.y));
  }
}

class MapScreen extends StatefulWidget {
  final LogService logService;
  const MapScreen({super.key, required this.logService});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _map = MapController();

  static const _assetMb = 'assets/maps/Jatinangor.mbtiles';
  static const _mbFileName = 'Jatinangor.mbtiles';

  _MbtilesReader? _mb;
  bool _loading = true;

  // >>> Tambahkan flag map siap
  bool _mapIsReady = false;

  List<LatLng> _raw = [];
  List<LatLng> _filt = [];
  LatLng _fallbackCenter = const LatLng(-6.9745, 107.6324);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _loadLogBuffers();
    await _openMb();
    if (!mounted) return;
    setState(() => _loading = false);

    // Fit setelah frame pertama (jika map belum siap, akan diulang pada onMapReady)
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToAllTracks());
  }

  Future<void> _openMb() async {
    try {
      final p = await _ensureMbtilesOnDisk(_assetMb, _mbFileName);
      final r = _MbtilesReader(p);
      await r.open();
      _mb = r;
    } catch (_) {
      _mb = null;
    }
  }

  Future<void> _loadLogBuffers() async {
    final raw = <LatLng>[];
    final filt = <LatLng>[];

    for (final s in widget.logService.recentRawBuffer) {
      raw.add(LatLng(s.lat, s.lon));
    }
    for (final s in widget.logService.recentFilteredBuffer) {
      filt.add(LatLng(s.lat, s.lon));
    }
    _raw = raw;
    _filt = filt;

    if (_filt.isNotEmpty) {
      _fallbackCenter = _filt.last;
    } else if (_raw.isNotEmpty) {
      _fallbackCenter = _raw.last;
    }
  }

  @override
  void dispose() {
    _mb?.close();
    super.dispose();
  }

  // === Auto-fit yang memperhitungkan AppBar/Status bar & safe-area ===
  void _fitToAllTracks() {
    if (!_mapIsReady) return; // <-- ganti _map.ready

    final mq = MediaQuery.of(context);
    final double topBars = mq.padding.top + kToolbarHeight;
    const double sidePad = 24.0;
    const double extraTop = 12.0;
    const double extraBottom = 48.0;

    final pad = EdgeInsets.fromLTRB(
      sidePad,
      topBars + extraTop,
      sidePad,
      mq.padding.bottom + extraBottom,
    );

    final all = <LatLng>[..._raw, ..._filt];

    if (all.isNotEmpty) {
      final b = LatLngBounds.fromPoints(all);
      _map.fitCamera(CameraFit.bounds(bounds: b, padding: pad));
      return;
    }

    final mb = _mb?.bounds;
    if (mb != null && mb.length == 4) {
      final b = LatLngBounds.fromPoints([
        LatLng(mb[1], mb[0]), // SW
        LatLng(mb[3], mb[2]), // NE
      ]);
      _map.fitCamera(CameraFit.bounds(bounds: b, padding: pad));
      return;
    }

    // fallback center
    final c = _mb?.center;
    final center = (c != null && c.length >= 2)
        ? LatLng(c[1], c[0])
        : _fallbackCenter;
    final z = (c != null && c.length >= 3) ? c[2].toDouble() : 16.0;
    _map.move(center, z);
  }

  CameraFit? _initialFitOrNull() {
    if (_raw.isNotEmpty || _filt.isNotEmpty) {
      final b = LatLngBounds.fromPoints([..._raw, ..._filt]);
      return CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(16));
    }
    final mb = _mb?.bounds;
    if (mb != null && mb.length == 4) {
      final b = LatLngBounds.fromPoints([
        LatLng(mb[1], mb[0]),
        LatLng(mb[3], mb[2]),
      ]);
      return CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(16));
    }
    return null;
  }

  (LatLng, double) _initialCenterZoom() {
    final c = _mb?.center;
    if (c != null && c.length >= 2) {
      final zoom = (c.length >= 3 ? c[2].toDouble() : 16.0);
      return (LatLng(c[1], c[0]), zoom);
    }
    return (_fallbackCenter, 16.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_mb == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Gagal membuka MBTiles.\nPastikan assets/maps/Jatinangor.mbtiles terdaftar di pubspec.yaml.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final fit = _initialFitOrNull();
    final (initCenter, initZoom) = _initialCenterZoom();

    return Scaffold(
      appBar: AppBar(title: const Text('Perbandingan Log: Raw vs Filtered')),
      body: SizedBox.expand(
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: initCenter,
            initialZoom: initZoom,
            initialCameraFit: fit,
            minZoom: (_mb!.minZoom ?? 0).toDouble(),
            maxZoom: (_mb!.maxZoom ?? 22).toDouble(),

            // Saat peta benar-benar siap, set flag & fit ulang
            onMapReady: () {
              _mapIsReady = true;
              Future.microtask(_fitToAllTracks);
            },
          ),
          children: [
            TileLayer(tileProvider: _MbtilesTileProvider(_mb!)),

            if (_raw.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _raw,
                    strokeWidth: 3.5,
                    color: const Color.fromRGBO(244, 67, 54, 0.80),
                  ),
                ],
              ),

            if (_filt.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _filt,
                    strokeWidth: 3.5,
                    color: const Color.fromRGBO(33, 150, 243, 0.80),
                  ),
                ],
              ),

            if (_raw.isNotEmpty)
              MarkerLayer(markers: _waypoints(_raw, const Color(0xFFF44336))),
            if (_filt.isNotEmpty)
              MarkerLayer(markers: _waypoints(_filt, const Color(0xFF2196F3))),

            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomRight,
              attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
            ),
          ],
        ),
      ),
    );
  }

  List<Marker> _waypoints(List<LatLng> points, Color color) {
    final markers = <Marker>[];
    for (int i = 0; i < points.length; i += 20) {
      markers.add(
        Marker(
          point: points[i],
          width: 10,
          height: 10,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      );
    }
    return markers;
  }
}
