// lib/screens/log_screen.dart
import 'package:flutter/material.dart';
import '../services/log_service.dart';

/// Konversi derajat bertanda (−180..+180 atau sembarang) → 0..360 untuk TAMPILAN.
double _toCompass360(double degSigned) {
  return (degSigned % 360 + 360) % 360;
}

class LogScreen extends StatelessWidget {
  final LogService logService;
  const LogScreen({super.key, required this.logService});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Logs'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'RAW'),
              Tab(text: 'FILTERED'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _RawList(),
            _FilteredList(),
          ],
        ),
      ),
    );
  }
}

/// RAW tab — keep-alive agar list tidak hilang saat pindah tab.
class _RawList extends StatefulWidget {
  const _RawList();

  @override
  State<_RawList> createState() => _RawListState();
}

class _RawListState extends State<_RawList>
    with AutomaticKeepAliveClientMixin<_RawList> {
  static const int _maxRows = 500;

  @override
  Widget build(BuildContext context) {
    super.build(context); // penting untuk keep-alive
    final log = (context.findAncestorWidgetOfExactType<LogScreen>())!.logService;

    return StreamBuilder<RawSample>(
      stream: log.recentRawStream,
      builder: (ctx, snap) {
        final items = <RawSample>[...log.recentRawBuffer];
        if (snap.hasData) {
          items.insert(0, snap.data!);
          if (items.length > _maxRows) items.removeRange(_maxRows, items.length);
        }

        if (items.isEmpty) {
          return const _EmptyState(label: 'Belum ada data RAW');
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = items[i];
            final hdg360 = _toCompass360(s.heading);
            return ListTile(
              leading: const Icon(Icons.gps_fixed, size: 22),
              dense: true,
              title: Text(s.t.toIso8601String(),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'lat=${s.lat.toStringAsFixed(6)}, '
                'lon=${s.lon.toStringAsFixed(6)}, '
                'hdg=${hdg360.toStringAsFixed(1)}°, '
                'acc=${s.acc?.toStringAsFixed(1) ?? '-'} m',
              ),
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

/// FILTERED tab — keep-alive juga.
class _FilteredList extends StatefulWidget {
  const _FilteredList();

  @override
  State<_FilteredList> createState() => _FilteredListState();
}

class _FilteredListState extends State<_FilteredList>
    with AutomaticKeepAliveClientMixin<_FilteredList> {
  static const int _maxRows = 500;

  @override
  Widget build(BuildContext context) {
    super.build(context); // penting untuk keep-alive
    final log = (context.findAncestorWidgetOfExactType<LogScreen>())!.logService;

    return StreamBuilder<FilteredSample>(
      stream: log.recentFilteredStream,
      builder: (ctx, snap) {
        final items = <FilteredSample>[...log.recentFilteredBuffer];
        if (snap.hasData) {
          items.insert(0, snap.data!);
          if (items.length > _maxRows) items.removeRange(_maxRows, items.length);
        }

        if (items.isEmpty) {
          return const _EmptyState(label: 'Belum ada data FILTERED');
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = items[i];
            final hdg360 = _toCompass360(s.heading);
            return ListTile(
              leading: const Icon(Icons.check_circle_outline, size: 22),
              dense: true,
              title: Text(s.t.toIso8601String(),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'lat=${s.lat.toStringAsFixed(6)}, '
                'lon=${s.lon.toStringAsFixed(6)}, '
                'hdg=${hdg360.toStringAsFixed(1)}°',
              ),
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          )),
    );
  }
}
