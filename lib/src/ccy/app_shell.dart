import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'data/store.dart';
import 'theme/tokens.dart';
import 'ui/gen_bar.dart';
import 'ui/hotkeys.dart';
import 'ui/info_window.dart';
import 'ui/layout.dart';
import 'ui/mods_window.dart';
import 'ui/px.dart';
import 'ui/top_bar.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.store,
    required this.onThemeSettings,
    required this.onToggleDemo,
    this.demoConnect = false,
    this.demoMods = false,
    this.demoMode = 'play',
  });
  final Store store;
  final VoidCallback onThemeSettings;
  final VoidCallback onToggleDemo;
  final bool demoConnect;
  final bool demoMods;
  final String demoMode;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _showInfo = true;
  late bool _showMods = widget.demoMods;
  bool _showGen = true;

  Size _genSize = const Size(L.genDefaultW, L.genDefaultH);
  bool _genTouched = false;

  late String _mode = widget.demoMode;

  List<String> _z = <String>['info', 'gen', 'mods'];

  /// 浮窗位置（设计坐标，左上角）。为空表示用默认停靠位。
  /// 一旦用户拖过就变成绝对坐标，不再跟着画布边缘走。
  final Map<String, Offset> _pos = <String, Offset>{};

  /// 当前正在被拖动的窗名（null = 没在拖）
  String? _dragName;
  double _dragMoved = 0;

  /// 窗头双击复位
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastTapName;

  double visHFor = 900;

  Offset _defaultPos(String name, double cw, double ch, double genH) {
    switch (name) {
      case 'mods':
        return Offset(L.margin, L.modsTop);
      case 'info':
        return Offset(cw - L.infoRight - InfoWindow.kWidth, L.infoTop);
      case 'gen':
        return Offset(L.genLeft, visHFor - L.genBottom - genH);
    }
    return Offset.zero;
  }

  Offset _posOf(String name, double cw, double ch, double genH) =>
      _pos[name] ?? _defaultPos(name, cw, ch, genH);

  /// 拖拽：夹在画布内，至少留 60px 可见（不允许整块拖出屏幕）
  void _drag(
    String name,
    Offset delta,
    double cw,
    double ch,
    double genH,
    double w,
    double h,
  ) {
    final cur = _posOf(name, cw, ch, genH);
    setState(() {
      _pos[name] = _clampPos(cur + delta, cw, ch, w, h);
    });
  }

  /// 把窗口夹在**可见范围**内：画布可能比窗口大，不能按画布算
  Offset _clampPos(Offset pos, double cw, double ch, double w, double h) {
    final roomX = (cw < visWFor ? cw : visWFor) - w;
    final roomY = (ch < visHFor ? ch : visHFor) - h;
    double inside(double v, double room) => room <= 0 ? 0 : v.clamp(0.0, room);
    return Offset(inside(pos.dx, roomX), inside(pos.dy, roomY));
  }

  double visWFor = 1440;

  void _raise(String name) {
    if (_z.isEmpty || _z.last == name) return;
    setState(() => _z = [..._z.where((n) => n != name), name]);
  }

  void _toggle(String which) {
    setState(() {
      if (which == 'info') _showInfo = !_showInfo;
      if (which == 'mod') _showMods = !_showMods;
      if (which == 'gen') {
        _showGen = !_showGen;
        if (!_showGen) {
          _genSize = const Size(L.genDefaultW, L.genDefaultH);
          _genTouched = false;
        }
      }
      // 重新显示时丢掉旧坐标：按当前画布重新算默认位，
      // 窗口被拉高/拉宽后浮窗仍然出现在看得见的地方
      final name = which == 'mod' ? 'mods' : which;
      _pos.remove(name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return LayoutBuilder(
      builder: (context, c) {
        final s = canvasScaleFor(
          c.maxWidth,
          c.maxHeight,
          designW: L.canvasW,
          designH: L.canvasH,
        );
        final cw = canvasWidthFor(c.maxWidth, c.maxHeight, designH: L.canvasH);
        final ch = canvasHeightFor(c.maxWidth, c.maxHeight, designH: L.canvasH);
        // 窗口实际可见的设计范围（画布可能比窗口大）
        final visW = c.maxWidth / s;
        final visH = c.maxHeight / s;
        visHFor = visH;
        visWFor = visW;
        gCanvasScale = s;
        gDpr = MediaQuery.devicePixelRatioOf(context);

        final genW = _genTouched ? _genSize.width : (cw - 40);
        final genH = _genSize.height.clamp(GenBar.minH, GenBar.maxH);

        return ColoredBox(
          color: T.desk,
          child: ClipRect(
            child: Stack(
              children: [
                // 图传在 play 模式下是**窗口级背景**，不参与画布缩放，
                // 所以永远不会因为画布装不下而露出黑边
                if (_mode == 'play') Positioned.fill(child: _backdrop()),
                // 画布永远钉在窗口左上角：顶栏才会紧贴顶部。
                // 不做居中——居中会让整块 HUD 在宽/高窗口里往下、往右漂。
                Positioned(
                  left: 0,
                  top: 0,
                  child: Transform.scale(
                    alignment: Alignment.topLeft,
                    scale: s,
                    child: SizedBox(
                      width: cw,
                      height: ch,
                      child: ListenableBuilder(
                        key: ObjectKey(store),
                        listenable: store,
                        builder: (context, _) => Hotkeys(
                          store: store,
                          child: Stack(
                            key: const ValueKey('board-stack'),
                            clipBehavior: Clip.hardEdge,
                            children: [
                              // play 模式下画布底必须透明，否则会盖住窗口级图传
                              if (_mode == 'monitor')
                                Positioned.fill(child: ColoredBox(color: T.bg)),
                              if (_mode == 'monitor') _videoCell(cw, ch, genH),
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: TopBar(
                                  store: store,
                                  onThemeSettings: widget.onThemeSettings,
                                  onExitDemo: widget.onToggleDemo,
                                  demoConnect: widget.demoConnect,
                                  openInfo: _showInfo,
                                  openMods: _showMods,
                                  openGen: _showGen,
                                  onToggle: _toggle,
                                  mode: _mode,
                                  onMode: (m) => setState(() => _mode = m),
                                  showToggles: _mode == 'play',
                                ),
                              ),
                              if (_mode == 'monitor')
                                ..._monitor(store, cw, ch, genH)
                              else
                                for (final name in _z)
                                  _floating(name, store, cw, ch, genW, genH),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// play：整窗背景。cover 铺满，永远没有黑边
  Widget _backdrop() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/ccy/img/feed.jpg',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.04),
              radius: 1.24,
              colors: [Color(0x0005080B), Color(0x3D05080B)],
              stops: [0.46, 1.0],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x4D05080B),
                Color(0x0005080B),
                Color(0x0005080B),
                Color(0x4205080B),
              ],
              stops: [0.0, 0.15, 0.80, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  /// monitor：图传是栅格里的格子，按源比例完整显示，空隙用模糊铺底
  Widget _videoCell(double cw, double ch, double genH) {
    final mainH = ch - L.monMainTop - L.monPad;
    final cellH = mainH - genH - L.gap;
    final cellW = cw - L.monModsW - L.monInfoW - L.gap * 3;
    return Positioned(
      left: L.monModsW + L.gap + L.monPad,
      top: L.monMainTop,
      width: cellW,
      height: cellH,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Image.asset(
                'assets/ccy/img/feed.jpg',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
              ),
            ),
            Image.asset(
              'assets/ccy/img/feed.jpg',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.04),
                  radius: 1.24,
                  colors: [Color(0x0005080B), Color(0x3D05080B)],
                  stops: [0.46, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _floating(
    String name,
    Store store,
    double cw,
    double ch,
    double genW,
    double genH,
  ) {
    Widget? content;
    double grabH = 40;
    double w = 320;
    double h = 400;
    if (name == 'info' && _showInfo) {
      content = InfoWindow(store: store);
      grabH = 40;
      w = InfoWindow.kWidth;
    } else if (name == 'gen' && _showGen) {
      grabH = 34;
      w = genW;
      h = genH;
      content = GenBar(
        store: store,
        onThemeSettings: widget.onThemeSettings,
        size: Size(genW, genH),
        onResize: (sz, topShift) => setState(() {
          _genTouched = true;
          final cur = _posOf('gen', cw, ch, genH);
          // 位置只按增量移动、高度直接取上报值：
          // 不要再拿"上一帧的 genH + 刚更新的 cur.dy"去反推底边，
          // 那样同帧多事件时底边会被一起带着上移。
          var top = cur.dy + topShift;
          var h = sz.height;
          if (top < 0) {
            // 顶到可见上边就停止长高（底边仍固定）
            h = (h + top).clamp(GenBar.minH, GenBar.maxH);
            top = 0;
          }
          _genSize = Size(sz.width, h);
          _pos['gen'] = _clampPos(Offset(cur.dx, top), cw, ch, sz.width, h);
        }),
      );
    } else if (name == 'mods' && _showMods) {
      content = ModsWindow(store: store, onOpenDemo: widget.onToggleDemo);
      grabH = 40;
      w = L.modsW;
      h = L.modsH;
    }
    if (content == null) return const SizedBox.shrink();
    final pos = _posOf(name, cw, ch, genH);
    return Positioned(
      key: ValueKey('win-$name'),
      left: pos.dx,
      top: pos.dy,
      // 用 Listener 直接判断"按下的位置在不在窗头"：
      // 不走手势竞技场，所以不会和窗头的按钮、滑杆抢事件。
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _raise(name);
          final dy = e.localPosition.dy;
          // 通用窗顶部 8px 留给"拉高"手柄
          final inGrab = dy <= grabH && !(name == 'gen' && dy < 8);
          _dragName = inGrab ? name : null;
        },
        onPointerMove: (e) {
          if (_dragName != name) return;
          _dragMoved += e.delta.distance;
          // 屏幕像素 → 设计像素：不除缩放，窗口会比鼠标跑得快
          _drag(name, e.delta / gCanvasScale, cw, ch, genH, w, h);
        },
        onPointerUp: (_) {
          // 窗头上连点两下 = 回到默认位置
          if (_dragName == name && _dragMoved < 4) {
            final now = DateTime.now();
            if (_lastTapName == name &&
                now.difference(_lastTapAt) <
                    const Duration(milliseconds: 350)) {
              setState(() => _pos.remove(name));
              _lastTapName = null;
            } else {
              _lastTapName = name;
              _lastTapAt = now;
            }
          }
          _dragName = null;
          _dragMoved = 0;
        },
        onPointerCancel: (_) {
          _dragName = null;
          _dragMoved = 0;
        },
        child: content,
      ),
    );
  }

  List<Widget> _monitor(Store store, double cw, double ch, double genH) {
    final mainH = ch - L.monMainTop - L.monPad;
    final rowH = mainH - genH - L.gap;
    final genW = cw - L.monGenLeft - L.monGenBottom;
    return [
      Positioned(
        key: const ValueKey('mon-info'),
        right: L.monPad,
        top: L.monMainTop,
        child: InfoWindow(store: store, heightOverride: rowH),
      ),
      Positioned(
        key: const ValueKey('mon-gen'),
        left: L.monGenLeft,
        bottom: L.monGenBottom,
        child: GenBar(
          store: store,
          onThemeSettings: widget.onThemeSettings,
          size: Size(genW, genH),
          onResize: (sz, _) =>
              setState(() => _genSize = Size(_genSize.width, sz.height)),
        ),
      ),
      Positioned(
        key: const ValueKey('mon-mods'),
        left: L.monPad,
        top: L.monMainTop,
        child: ModsWindow(
          store: store,
          onOpenDemo: widget.onToggleDemo,
          width: L.monModsW,
          height: mainH,
        ),
      ),
    ];
  }
}
