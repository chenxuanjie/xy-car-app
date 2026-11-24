import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport.dart';

final class WebSocketTransport implements Transport {
  static const _connectTimeout = Duration(seconds: 5);

  WebSocketChannel? _channel;

  @override
  Future<void> open(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    await channel.ready.timeout(_connectTimeout);
  }

  @override
  Stream<String> get stream =>
      _channel!.stream.where((message) => message is String).cast<String>();

  @override
  void send(String message) => _channel!.sink.add(message);

  @override
  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }
}
