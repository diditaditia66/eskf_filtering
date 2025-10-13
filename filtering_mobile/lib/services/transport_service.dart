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

  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  Future<void> connect(
    String wsUrl, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await close(); // bersihkan koneksi lama
    try {
      _logCtrl.add('WS: connecting to $wsUrl ...');

      _socket = await WebSocket.connect(wsUrl)
          .timeout(timeout, onTimeout: () => throw TimeoutException('WS: connect timeout'));
      _socket!.pingInterval = const Duration(seconds: 15);

      _ch = IOWebSocketChannel(_socket!);

      _sub = _ch!.stream.listen(
        (msg) => _logCtrl.add('WS <= $msg'),
        onDone: () {
          _logCtrl.add('WS: closed by remote');
          _connCtrl.add(false);
          _cleanup();
        },
        onError: (e, st) {
          _logCtrl.add('WS: error $e');
          _connCtrl.add(false);
          _cleanup();
        },
        cancelOnError: true,
      );

      _logCtrl.add('WS: connected');
      _connCtrl.add(true);
    } catch (e) {
      _logCtrl.add('WS: connect failed: $e');
      _connCtrl.add(false);
      _cleanup();
      rethrow;
    }
  }

  void sendFusionSample({
    required double lat,
    required double lon,
    required double headingDeg,
    required DateTime timestamp,
  }) {
    final ch = _ch;
    if (ch == null) return;

    final msg = jsonEncode({
      'type': 'filtered_pose',
      'lat': lat,
      'lon': lon,
      'heading_deg': headingDeg,
      'sent_at': timestamp.toIso8601String(),
    });

    ch.sink.add(msg);
    _logCtrl.add('WS => $msg');
  }

  Future<void> close() async {
    try {
      await _sub?.cancel();
      await _ch?.sink.close();
      try { await _socket?.close(); } catch (_) {}
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
    _logCtrl.close();
    _connCtrl.close();
  }
}
