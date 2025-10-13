import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../services/log_service.dart';

class MapScreen extends StatefulWidget {
  final LogService logService;
  const MapScreen({super.key, required this.logService});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _map = MapController();

  List<LatLng> _raw = [];
  List<LatLng> _filtered = [];
  LatLng? _center;

  @override
  void initState() {
    super.initState();
    _loadLogData();
  }

  Future<void> _loadLogData() async {
    final raw = <LatLng>[];
    final filtered = <LatLng>[];

    for (final r in widget.logService.recentRawBuffer) {
      raw.add(LatLng(r.lat, r.lon));
    }
    for (final f in widget.logService.recentFilteredBuffer) {
      filtered.add(LatLng(f.lat, f.lon));
    }

    if (filtered.isNotEmpty) {
      _center = filtered.last;
    } else if (raw.isNotEmpty) {
      _center = raw.last;
    } else {
      _center = const LatLng(-6.9745, 107.6324); // fallback kampus
    }

    setState(() {
      _raw = raw;
      _filtered = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final token = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    if (token.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text(
            'MAPBOX_ACCESS_TOKEN tidak ditemukan di file .env',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final center = _center ?? const LatLng(-6.9745, 107.6324);

    return Scaffold(
      appBar: AppBar(title: const Text('Perbandingan Log: Raw vs Filtered')),
      body: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 16,
        ),
        children: [
          // Tile Mapbox (online, tanpa caching)
          TileLayer(
            urlTemplate:
                'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token={token}',
            additionalOptions: {'token': token},
            userAgentPackageName: 'com.example.filtering_mobile',
          ),

          // Jalur RAW (merah)
          if (_raw.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _raw,
                  strokeWidth: 3.5,
                  color: const Color.fromRGBO(244, 67, 54, 0.80), // red 500 @ 0.8
                ),
              ],
            ),

          // Jalur FILTERED (biru)
          if (_filtered.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _filtered,
                  strokeWidth: 3.5,
                  color: const Color.fromRGBO(33, 150, 243, 0.80), // blue 500 @ 0.8
                ),
              ],
            ),

          // Waypoint bulat setiap ~20 titik
          if (_raw.isNotEmpty) MarkerLayer(markers: _waypoints(_raw, const Color(0xFFF44336))),
          if (_filtered.isNotEmpty)
            MarkerLayer(markers: _waypoints(_filtered, const Color(0xFF2196F3))),

          // Attribution
          const RichAttributionWidget(
            alignment: AttributionAlignment.bottomRight,
            attributions: [
              TextSourceAttribution('© Mapbox'),
              TextSourceAttribution('© OpenStreetMap contributors'),
            ],
          ),
        ],
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
