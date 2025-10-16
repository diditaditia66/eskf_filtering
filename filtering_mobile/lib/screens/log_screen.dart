// lib/screens/log_screen.dart
import 'package:flutter/material.dart';
import '../services/log_service.dart';

double _toCompass360(double degSigned) {
  return (degSigned % 360 + 360) % 360;
}

class LogScreen extends StatefulWidget {
  final LogService logService;
  const LogScreen({super.key, required this.logService});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  // Token untuk memaksa rebuild ulang anak-anak StreamBuilder setelah clearAll()
  int _resetToken = 0;

  Future<void> _confirmClearLogs() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus semua log?'),
        content: const Text('Tindakan ini akan menghapus seluruh data log yang tersimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await widget.logService.clearAll();
      if (!mounted) return;
      // Paksa kedua tab re-build (StreamBuilder kehilangan snapshot lama)
      setState(() => _resetToken++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua log berhasil dihapus')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Logs'),
          actions: [
            IconButton(
              tooltip: 'Clear logs',
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              onPressed: _confirmClearLogs,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'RAW'),
              Tab(text: 'FILTERED'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // KUNCIKAN dengan resetToken supaya StreamBuilder di bawah benar-benar baru
            _RawList(key: ValueKey('raw-$_resetToken'), logService: widget.logService),
            _FilteredList(key: ValueKey('filt-$_resetToken'), logService: widget.logService),
          ],
        ),
      ),
    );
  }
}

/// RAW tab
class _RawList extends StatefulWidget {
  final LogService logService;
  const _RawList({super.key, required this.logService});
  @override
  State<_RawList> createState() => _RawListState();
}

class _RawListState extends State<_RawList>
    with AutomaticKeepAliveClientMixin<_RawList> {
  static const int _maxRows = 500;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final log = widget.logService;

    return StreamBuilder<RawSample>(
      stream: log.recentRawStream,
      builder: (ctx, snap) {
        // Ambil buffer yang SUDAH kosong setelah clearAll()
        final items = <RawSample>[...log.recentRawBuffer];

        // Jika stream baru mengirim event, tambahkan ke atas (hingga _maxRows)
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

/// FILTERED tab
class _FilteredList extends StatefulWidget {
  final LogService logService;
  const _FilteredList({super.key, required this.logService});
  @override
  State<_FilteredList> createState() => _FilteredListState();
}

class _FilteredListState extends State<_FilteredList>
    with AutomaticKeepAliveClientMixin<_FilteredList> {
  static const int _maxRows = 500;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final log = widget.logService;

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
      child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
    );
  }
}
