import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class VpnConnectionManager {
  final String baseUrl = 'https://api.vpn4tv.com';
  final String uuid;
  final void Function(dynamic) onMessage;
  final void Function(dynamic) onError;
  final Duration pollingInterval;

  Timer? _pollingTimer;
  bool _isConnected = false;

  VpnConnectionManager({
    required this.uuid,
    required this.onMessage,
    required this.onError,
    this.pollingInterval = const Duration(seconds: 30),
  });

  void connect() {
    _isConnected = true;
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(pollingInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (!_isConnected) return;

    try {
      final response = await http.get(Uri.parse('$baseUrl/poll?uuid=$uuid'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['type'] != 'timeout') {
          onMessage(data);
        }
      } else {
        onError('Poll failed with status: ${response.statusCode}');
      }
    } catch (e) {
      onError(e);
    }
  }

  /// Force an immediate poll (e.g. when app returns from background)
  void forcePoll() {
    if (_isConnected) _poll();
  }

  void disconnect() {
    _isConnected = false;
    _pollingTimer?.cancel();
  }

  bool get isConnected => _isConnected;
}
