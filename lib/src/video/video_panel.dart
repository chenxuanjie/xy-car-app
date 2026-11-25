import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../app_modules.dart' show isOfflineWifiOrigin, localized;
import '../ccy/data/store.dart';
import '../network/service_http_client.dart';
import '../station/vehicle_connections.dart';
import 'video_profile.dart';

class VehicleVideo extends StatefulWidget {
  const VehicleVideo({super.key, required this.store, required this.profile});

  final Store store;
  final VideoProfile profile;

  @override
  State<VehicleVideo> createState() => _VehicleVideoState();
}

class _VehicleVideoState extends State<VehicleVideo> {
  int _attempt = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final target = widget.store.activeTarget;
      if (target == null) {
        return _VideoMessage(localized(context, '无信号输入', 'NO SIGNAL'));
      }
      if (target.route != VehicleRoute.lan) {
        return _VideoMessage(
          localized(context, '公网图传尚未接入', 'Remote video is not configured'),
        );
      }
      final path = '/${widget.profile.path}/whep';
      final endpoint =
          isOfflineWifiOrigin && target.endpoint.host == Uri.base.host
          ? Uri.base.resolve('/media$path')
          : Uri(
              scheme: 'http',
              host: target.endpoint.host,
              port: 8889,
              path: path,
            );
      return _WhepVideo(
        key: ValueKey((endpoint, _attempt)),
        endpoint: endpoint,
        onRetry: () => setState(() => _attempt++),
      );
    },
  );
}

class _VideoMessage extends StatelessWidget {
  const _VideoMessage(this.text, {this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_outlined, color: Colors.white54, size: 32),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: Colors.white70)),
          if (onRetry case final retry?)
            TextButton(
              onPressed: retry,
              child: Text(localized(context, '重试', 'Retry')),
            ),
        ],
      ),
    ),
  );
}

class _WhepVideo extends StatefulWidget {
  const _WhepVideo({
    required super.key,
    required this.endpoint,
    required this.onRetry,
  });

  final Uri endpoint;
  final VoidCallback onRetry;

  @override
  State<_WhepVideo> createState() => _WhepVideoState();
}

class _WhepVideoState extends State<_WhepVideo> {
  static const _iceTimeout = Duration(seconds: 3);
  static const _requestTimeout = Duration(seconds: 10);
  static const _firstFrameTimeout = Duration(seconds: 15);
  static const _deleteTimeout = Duration(seconds: 2);
  final _renderer = RTCVideoRenderer();
  final _http = createServiceHttpClient();
  RTCPeerConnection? _peer;
  Uri? _resource;
  late final Future<void> _opening;
  Future<void>? _closing;
  Timer? _firstFrameTimer;
  bool _initialized = false;
  bool _hasPicture = false;
  bool _failed = false;
  bool _disposed = false;

  bool get _active => !_disposed && !_failed;

  @override
  void initState() {
    super.initState();
    _renderer.addListener(_onVideoSize);
    _firstFrameTimer = Timer(_firstFrameTimeout, () {
      _fail(TimeoutException('No WHEP video frame', _firstFrameTimeout));
    });
    _opening = _connect();
  }

  Future<void> _connect() async {
    try {
      await _renderer.initialize();
      if (!_active) return;
      setState(() => _initialized = true);

      final peer = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': <Map<String, Object>>[],
      });
      _peer = peer;
      if (!_active) return;
      peer.onTrack = (event) {
        if (_active &&
            event.track.kind == 'video' &&
            event.streams.isNotEmpty) {
          _renderer.srcObject = event.streams.first;
        }
      };
      peer.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _fail(StateError('WHEP media connection failed'));
        }
      };
      await peer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      final gathered = Completer<void>();
      const complete = RTCIceGatheringState.RTCIceGatheringStateComplete;
      peer.onIceGatheringState = (state) {
        if (state == complete && !gathered.isCompleted) gathered.complete();
      };
      await peer.setLocalDescription(await peer.createOffer());
      if (await peer.getIceGatheringState() != complete) {
        await gathered.future.timeout(_iceTimeout);
      }
      peer.onIceGatheringState = null;
      if (!_active) return;
      final offer = (await peer.getLocalDescription())?.sdp;
      if (offer == null || offer.isEmpty) {
        throw StateError('WHEP offer is empty');
      }
      final response = await _http
          .post(
            widget.endpoint,
            headers: const {'Content-Type': 'application/sdp'},
            body: offer,
          )
          .timeout(_requestTimeout);
      final location = response.headers['location'];
      if (response.statusCode != 201 || location == null) {
        throw StateError('WHEP failed with HTTP ${response.statusCode}');
      }
      _resource = widget.endpoint.resolve(location);
      if (_active) {
        await peer.setRemoteDescription(
          RTCSessionDescription(response.body, 'answer'),
        );
      }
    } catch (error) {
      _fail(error);
    }
  }

  void _onVideoSize() {
    if (!_active || _hasPicture || _renderer.videoWidth < 1) return;
    _firstFrameTimer?.cancel();
    setState(() => _hasPicture = true);
  }

  void _fail(Object error) {
    if (!_active) return;
    debugPrint('Video playback: $error');
    _firstFrameTimer?.cancel();
    setState(() => _failed = true);
    _scheduleClose();
  }

  void _scheduleClose() {
    _closing ??= _opening.then((_) => _release());
    unawaited(_closing!);
  }

  Future<void> _release() async {
    try {
      if (_resource case final resource?) {
        await _http.delete(resource).timeout(_deleteTimeout);
      }
    } catch (error) {
      debugPrint('Close WHEP resource: $error');
    } finally {
      _http.close();
      try {
        await _peer?.dispose();
      } finally {
        await _renderer.dispose();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _firstFrameTimer?.cancel();
    _scheduleClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _VideoMessage(
        localized(context, '视频连接失败', 'Video connection failed'),
        onRetry: widget.onRetry,
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_initialized) RTCVideoView(_renderer),
          if (!_hasPicture)
            Center(
              child: Text(localized(context, '正在连接视频…', 'Connecting video…')),
            ),
        ],
      ),
    );
  }
}
