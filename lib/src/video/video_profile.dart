enum VideoResolution {
  p480('480p'),
  p720('720p'),
  p1080('1080p');

  const VideoResolution(this.value);

  final String value;

  static VideoResolution fromPreference(String value) =>
      values.firstWhere((resolution) => resolution.value == value);
}

enum VideoFrameRate {
  fps15(15),
  fps25(25),
  fps30(30);

  const VideoFrameRate(this.fps);

  final int fps;
  String get value => '$fps';
  String get label => '$fps fps';

  static VideoFrameRate fromPreference(String value) =>
      values.firstWhere((frameRate) => frameRate.value == value);
}

final class VideoProfile {
  const VideoProfile({required this.resolution, required this.frameRate});

  final VideoResolution resolution;
  final VideoFrameRate frameRate;

  String get path => 'cam_${resolution.value}_${frameRate.fps}';
}
