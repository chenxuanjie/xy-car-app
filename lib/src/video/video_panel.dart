import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../app_modules.dart' show isBoardWeb, localized;
import '../ccy/data/store.dart';
import '../network/service_http_client.dart';
import '../station/vehicle_discovery.dart';
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
  bool _visible = true;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => setState(() => _visible = false),
      onShow: () => setState(() => _visible = true),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final target = widget.store.activeTarget;
      if (target == null || !_visible) {
        return _VideoMessage(localized(context, '无信号输入', 'NO SIGNAL'));
      }
      final remote = target.route == VehicleRoute.remote;
      final path = '/${widget.profile.path}/whep';
      final Uri? endpoint = remote
          ? null
          : isBoardWeb && target.endpoint.host == Uri.base.host
          ? Uri.base.resolve('/media$path')
          : Uri(
              scheme: 'http',
              host: target.endpoint.host,
              port: 8889,
              path: path,
            );
      return _WhepVideo(
        key: ValueKey((target, widget.profile.path, _attempt)),
        lanEndpoint: endpoint,
        relay: remote ? widget.store : null,
        profile: widget.profile.path,
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
    required this.lanEndpoint,
    required this.relay,
    required this.profile,
    required this.onRetry,
  });

  final Uri? lanEndpoint;
  final Store? relay;
  final String profile;
  final VoidCallback onRetry;

  @override
  State<_WhepVideo> createState() => _WhepVideoState();
}

class _WhepVideoState extends State<_WhepVideo> {
  static const _iceTimeout = Duration(seconds: 3);
  static const _requestTimeout = Duration(seconds: 10);
  static const _firstFrameTimeout = Duration(seconds: 15);
  static const _remoteFrameTimeout = Duration(seconds: 25);
  static const _leaseRenewal = Duration(seconds: 5);
  static const _deleteTimeout = Duration(seconds: 2);
  final _renderer = RTCVideoRenderer();
  final _http = createServiceHttpClient();
  RTCPeerConnection? _peer;
  Uri? _resource;
  late final Future<void> _opening;
  Future<void>? _closing;
  Timer? _firstFrameTimer;
  Timer? _renewalTimer;
  String? _lease;
  String? _relayError;
  bool _initialized = false;
  bool _hasPicture = false;
  bool _failed = false;
  bool _disposed = false;

  bool get _active => !_disposed && !_failed;

  @override
  void initState() {
    super.initState();
    _renderer.addListener(_onVideoSize);
    final frameTimeout = widget.relay == null
        ? _firstFrameTimeout
        : _remoteFrameTimeout;
    _firstFrameTimer = Timer(frameTimeout, () {
      _fail(TimeoutException('No WHEP video frame', frameTimeout));
    });
    _opening = _connect();
  }

  Future<void> _connect() async {
    try {
      final endpoint = await _endpoint();
      if (!_active) return;
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
      const readinessDelays = [500, 1000, 1500, 2000, 3000, 3000];
      for (var attempt = 0; _active; attempt++) {
        final response = await _http
            .post(
              endpoint,
              headers: const {'Content-Type': 'application/sdp'},
              body: offer,
            )
            .timeout(_requestTimeout);
        final location = response.headers['location'];
        if (response.statusCode == 201 && location != null) {
          final resource = endpoint.resolve(location);
          if (resource.origin != endpoint.origin) {
            throw StateError('Invalid WHEP session origin');
          }
          _resource = resource;
          if (_active) {
            await peer.setRemoteDescription(
              RTCSessionDescription(response.body, 'answer'),
            );
          }
          return;
        }
        if (widget.relay == null ||
            (response.statusCode != 404 && response.statusCode != 503) ||
            attempt == readinessDelays.length) {
          throw StateError('WHEP failed with HTTP ${response.statusCode}');
        }
        await Future<void>.delayed(
          Duration(milliseconds: readinessDelays[attempt]),
        );
      }
    } catch (error) {
      _fail(error);
    }
  }

  Future<Uri> _endpoint() async {
    if (widget.lanEndpoint case final endpoint?) return endpoint;
    final relay = widget.relay!;
    final lease = relay.newVideoLease();
    _lease = lease;
    final status = await relay.requestVideo(lease, profile: widget.profile);
    final url = status['whep_url'];
    final endpoint = url is String ? Uri.tryParse(url) : null;
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty) {
      throw StateError('Invalid public WHEP endpoint');
    }
    if (_active) _scheduleRenewal();
    return endpoint;
  }

  void _scheduleRenewal() {
    _renewalTimer = Timer(_leaseRenewal, () async {
      if (!_active) return;
      try {
        await widget.relay!.requestVideo(_lease!, profile: widget.profile);
        if (_active) _scheduleRenewal();
      } catch (error) {
        _fail(error);
      }
    });
  }

  void _stopRelay() {
    _renewalTimer?.cancel();
    final lease = _lease;
    _lease = null;
    if (lease != null) widget.relay!.requestVideo(lease).ignore();
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
    if (error is GatewayRequestException) _relayError = error.code;
    setState(() => _failed = true);
    _stopRelay();
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
    _stopRelay();
    _scheduleClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      final message = switch (_relayError) {
        'video_relay_unconfigured' => localized(
          context,
          '车辆尚未配置公网图传',
          'Vehicle video relay is not configured',
        ),
        'video_profile_busy' => localized(
          context,
          '其他观看端正在使用不同画质',
          'Another viewer is using a different profile',
        ),
        _ => localized(context, '视频连接失败', 'Video connection failed'),
      };
      return _VideoMessage(message, onRetry: widget.onRetry);
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
