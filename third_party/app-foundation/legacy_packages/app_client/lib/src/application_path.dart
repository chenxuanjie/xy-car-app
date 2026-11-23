import 'failure.dart';

/// Scoped clients cannot select another module through a feature-supplied path.
String applicationPath(String path, String? applicationId) {
  final relative = path.startsWith('/') ? path.substring(1) : path;
  if (applicationId == null) return relative;
  final segments = Uri.parse(relative).pathSegments;
  if (segments.length >= 3 && segments[0] == 'v1' && segments[1] == 'apps') {
    if (segments[2] == applicationId) return relative;
  } else if (relative.startsWith('v1/')) {
    return 'v1/apps/$applicationId/${relative.substring(3)}';
  }
  throw const AppClientFailure('服务请求的应用路径不正确', code: 'invalid_path');
}
