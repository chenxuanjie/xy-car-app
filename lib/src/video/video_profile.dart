enum VideoProfile {
  low('480p', 15),
  standard('720p', 25),
  high('1080p', 30);

  const VideoProfile(this.resolution, this.fps);

  final String resolution;
  final int fps;

  String get label => '$resolution / $fps fps';
  String get path => 'cam_$resolution';

  static VideoProfile fromPreference(String value) =>
      values.firstWhere((profile) => profile.resolution == value);
}
