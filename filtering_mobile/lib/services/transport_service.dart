// lib/services/transport_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io'; // untuk WebSocket.connect (bisa di-await)
import 'package:web_socket_channel/io.dart';

class TransportService {
  IOWebSocketChannel? _ch;
  WebSocket? _socket; // simpan socket asli utk cek state
  StreamSubscription? _sub;

  final _logCtrl = StreamController<String>.broadcast();
  Stream<String> get logStream => _logCtrl.stream;

  // Stream status koneksi (true/false)
  final _connCtrl = StreamController<bool>.broadcast();
  Stream<bool> get connectedStream => _connCtrl.stream;

  // RTT stream (ms)
  final _rttCtrl = StreamController<double>.broadcast();
  Stream<double> get rttStream => _rttCtrl.stream;
  DateTime? _lastSendAt;

  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  // ---------- Tambahan: retry/backoff ----------
  final Duration _backoffBase = const Duration(seconds: 1);
  final Duration _backoffMax  = const Duration(seconds: 30);
  bool _shouldReconnect = false;
  String? _lastUrl;

  // ---------- Tambahan: outbox buffer ----------
  final List<String> _outbox = <String>[];
  final int _maxOutbox = 200;
  int get queueLength => _outbox.length;

  Future<void> connect(
    String wsUrl, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _lastUrl = wsUrl;
    await close(); // bersihkan koneksi lama
    try {
      _logCtrl.add('WS: connecting to $wsUrl ...');

      _socket = await WebSocket.connect(wsUrl)
          .timeout(timeout, onTimeout: () => throw TimeoutException('WS: connect timeout'));
      _socket!.pingInterval = const Duration(seconds: 15);

      _ch = IOWebSocketChannel(_socket!);

      _sub = _ch!.stream.listen(
        (msg) {
          // Log inbound messages (ACK/health dsb.)
          _logCtrl.add('WS <= $msg');

          // Hitung RTT jika server kirim {"ack": true, ...}
          try {
            final d = jsonDecode(msg);
            if (d is Map && d['ack'] == true && _lastSendAt != null) {
              final rtt = DateTime.now()
                  .difference(_lastSendAt!)
                  .inMilliseconds
                  .toDouble();
              _rttCtrl.add(rtt);
            }
          } catch (_) {}
        },
        onDone: () {
          _logCtrl.add('WS: closed by remote');
          _connCtrl.add(false);
          _cleanup();
          // Jika mode auto-reconnect aktif, coba lagi
          if (_shouldReconnect && _lastUrl != null) {
            // non-blocking relaunch
            () => connectWithRetry(_lastUrl!);
            unawaited(connectWithRetry(_lastUrl!));
          }
        },
        onError: (e, st) {
          _logCtrl.add('WS: error $e');
          _connCtrl.add(false);
          _cleanup();
          if (_shouldReconnect && _lastUrl != null) {
            unawaited(connectWithRetry(_lastUrl!));
          }
        },
        cancelOnError: true,
      );

      _logCtrl.add('WS: connected');
      _connCtrl.add(true);

      // Flush pesan yang sempat di-queue
      _flushOutbox();
    } catch (e) {
      _logCtrl.add('WS: connect failed: $e');
      _connCtrl.add(false);
      _cleanup();
      rethrow;
    }
  }

  /// Connect dengan auto-retry (exponential backoff).
  /// Panggil ini dari UI alih-alih `connect(...)` biasa jika ingin auto-reconnect.
  Future<void> connectWithRetry(
    String wsUrl, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _shouldReconnect = true;
    _lastUrl = wsUrl;
    Duration delay = _backoffBase;

    if (isConnected) return;

    while (_shouldReconnect && !isConnected) {
      try {
        await connect(wsUrl, timeout: timeout);
        return; // sukses
      } catch (e) {
        _logCtrl.add('WS: retry in ${delay.inSeconds}s');
        await Future.delayed(delay);
        final nextSeconds = (delay.inSeconds * 2).clamp(
          _backoffBase.inSeconds,
          _backoffMax.inSeconds,
        );
        delay = Duration(seconds: nextSeconds);
      }
    }
  }

  /// Hentikan koneksi dan matikan auto-retry.
  Future<void> closeAndStopRetry() async {
    _shouldReconnect = false;
    await close();
  }

  void sendFusionSample({
    required double lat,
    required double lon,
    required double headingDeg,
    required DateTime timestamp,
    double? accuracyM, // opsional untuk ikut dikirim
  }) {
    final payload = <String, dynamic>{
      'type': 'filtered_pose',
      'lat': lat,
      'lon': lon,
      'heading_deg': headingDeg,
      'sent_at': timestamp.toIso8601String(),
      if (accuracyM != null) 'acc_m': accuracyM,
    };

    final msg = jsonEncode(payload);

    if (!isConnected || _ch == null) {
      // Queue dulu jika belum terhubung
      if (_outbox.length >= _maxOutbox) _outbox.removeAt(0);
      _outbox.add(msg);
      _logCtrl.add('WS [queued] => $msg');
      return;
    }

    // Jika terhubung, flush antrian (kalau ada) lalu kirim
    _flushOutbox();
    _lastSendAt = DateTime.now();
    _ch!.sink.add(msg);
    _logCtrl.add('WS => $msg');
  }

  void _flushOutbox() {
    if (!isConnected || _ch == null) return;
    while (_outbox.isNotEmpty) {
      final m = _outbox.removeAt(0);
      _lastSendAt = DateTime.now();
      _ch!.sink.add(m);
      _logCtrl.add('WS [flush] => $m');
    }
  }

  Future<void> close() async {
    try {
      await _sub?.cancel();
      await _ch?.sink.close();
      try {
        await _socket?.close();
      } catch (_) {}
    } finally {
      _cleanup();
      _connCtrl.add(false);
      _logCtrl.add('WS: closed');
    }
  }

  void _cleanup() {
    _sub = null;
    _ch = null;
    _socket = null;
  }

  void dispose() {
    _shouldReconnect = false;
    _logCtrl.close();
    _connCtrl.close();
    _rttCtrl.close();
  }
}
