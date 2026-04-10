import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:grpc/grpc.dart';
import 'package:http2/transport.dart';

/// gRPC transport connector that calls VpnService.protect() on each TCP socket.
/// Prevents gRPC traffic from being routed through the VPN TUN interface
/// on multi-user Android TV devices where addDisallowedApplication(self) causes SIGABRT.
class ProtectedTransportConnector implements ClientTransportConnector {
  final String host;
  final int port;
  final ChannelOptions options;
  final MethodChannel _methodChannel;
  Socket? _socket;
  final _doneCompleter = Completer<void>();

  ProtectedTransportConnector(
    this.host,
    this.port,
    this._methodChannel, {
    this.options = const ChannelOptions(),
  });

  @override
  String get authority => '$host:$port';

  @override
  Future<ClientTransportConnection> connect() async {
    _socket = await Socket.connect(host, port, timeout: options.connectTimeout);
    _socket!.setOption(SocketOption.tcpNoDelay, true);

    // Protect the socket so it bypasses VPN TUN routing.
    // We pass the local port and Kotlin finds the fd via /proc/self/net/tcp.
    try {
      final localPort = _socket!.port;
      await _methodChannel.invokeMethod('protect_socket', {'localPort': localPort});
    } catch (_) {
      // Non-critical: if protect fails, gRPC may still work (loopback might not go through TUN)
    }

    final securityContext = options.credentials.securityContext;
    Stream<List<int>> incoming = _socket!;

    if (securityContext != null) {
      final secureSocket = await SecureSocket.secure(
        _socket!,
        host: options.credentials.authority ?? host,
        context: securityContext,
      );
      _socket = secureSocket;
      incoming = secureSocket;
    }

    return ClientTransportConnection.viaStreams(incoming, _socket!);
  }

  @override
  Future get done => _doneCompleter.future;

  @override
  void shutdown() {
    _socket?.destroy();
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}
