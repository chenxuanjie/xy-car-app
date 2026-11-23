part of '../../main.dart';

// Artwork from usv_ground_station and Flutter's Material Icons.
enum _StationGlyph {
  accountCircle,
  activity,
  arrowDown,
  arrowLeft,
  arrowRight,
  arrowUp,
  cloudDownload,
  fileText,
  globe,
  lineChart,
  list,
  manageAccounts,
  map,
  mapAddPin,
  mapHand,
  mapLocate,
  mapPin,
  menu,
  navigation,
  pause,
  play,
  plus,
  refreshCw,
  send,
  server,
  settings,
  sidebar,
  stationAntenna,
  trash2,
  video,
  x,
}

class _StationIcon extends StatelessWidget {
  const _StationIcon(this.glyph, {this.color, this.size});

  final _StationGlyph glyph;
  final Color? color;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final extent = size ?? theme.size ?? 24;
    final foreground = color ?? theme.color ?? Colors.black;
    final tint = foreground.withValues(
      alpha: foreground.a * (theme.opacity ?? 1),
    );

    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SvgPicture.asset(
        'assets/icons/station/${glyph.name}.svg',
        width: extent,
        height: extent,
        colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
        excludeFromSemantics: true,
      ),
    );
  }
}
