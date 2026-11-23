final class InstalledAppVersion {
  const InstalledAppVersion({
    required this.appId,
    required this.versionName,
    required this.buildNumber,
    required this.platform,
    required this.architecture,
    this.channel = 'stable',
  });

  final String appId;
  final String versionName;
  final int buildNumber;
  final String platform;
  final String architecture;
  final String channel;
}
