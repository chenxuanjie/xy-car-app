import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import 'kit.dart';
import 'layout.dart';
import 'module_card.dart';
import 'module_nav.dart';
import 'module_state.dart';
import 'strings.dart';
import 'window_frame.dart';

/// 模块窗：外壳 + 滚动 + 组装。
/// 展开/选中状态在 ModuleListState 里，卡片与导航各自独立成文件。
class ModsWindow extends StatefulWidget {
  const ModsWindow({
    super.key,
    required this.store,
    required this.onOpenDemo,
    this.width = L.modsW,
    this.height = L.modsH,
  });
  final Store store;
  final VoidCallback onOpenDemo;
  final double width;
  final double height;

  @override
  State<ModsWindow> createState() => _ModsWindowState();
}

class _ModsWindowState extends State<ModsWindow> {
  final ModuleListState _state = ModuleListState();
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};
  final ScrollController _scroll = ScrollController();

  Store get store => widget.store;

  GlobalKey _keyFor(ModuleVm m) =>
      _keys.putIfAbsent(m.identity, () => GlobalKey());

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 全展开 / 全收起后回到顶部
  void _backToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _toggle(ModuleVm m) => setState(() => _state.toggle(m.identity));

  void _open(ModuleVm m) {
    setState(() => _state.openOnly(m.identity));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[m.identity]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        alignment: 0.08,
      );
    });
  }

  void _select(ModuleVm m) => setState(() => _state.select(m.identity));

  void _expandAll() {
    setState(() => _state.expandAll());
    _backToTop();
  }

  void _collapseAll() {
    setState(() => _state.collapseAll());
    _backToTop();
  }

  @override
  Widget build(BuildContext context) {
    // 顺序由 _state.order 持有：导航栏长按排序后，卡片列表跟着换序
    _state.syncModules(store.modules.map((m) => m.identity).toList());
    if (_state.selected == null && store.modules.isNotEmpty) {
      _state.selected = store.modules.first.identity;
    }
    store.syncSelection(_state.selected);

    final byId = {for (final m in store.modules) m.identity: m};
    final ordered = [
      for (final id in _state.order)
        if (byId[id] != null) byId[id]!,
    ];

    if (ordered.isEmpty) {
      return WindowFrame(
        width: widget.width,
        height: widget.height,
        fill: T.slot,
        title: S.modules,
        dimmed: store.dataStale,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(S.noModuleData, style: sans(12, T.text2)),
              if (!store.isDemo)
                TextButton(
                  onPressed: widget.onOpenDemo,
                  child: const Text(S.openDemoModules),
                ),
            ],
          ),
        ),
      );
    }

    return WindowFrame(
      width: widget.width,
      height: widget.height,
      fill: T.slot,
      title: S.modules,
      dimmed: store.dataStale,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconBtn(Icons.unfold_more, _expandAll, S.expandAll),
          const SizedBox(width: 6),
          _iconBtn(Icons.unfold_less, _collapseAll, S.collapseAll),
        ],
      ),
      child: Row(
        // 关键：默认 crossAxisAlignment.center 会让卡片列按内容高度收缩后
        // 在窗口里垂直居中；必须拉伸，列表才从顶部开始
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModuleNav(
            modules: ordered,
            numberOf: _state.numberOf,
            selectedId: _state.selected,
            stale: store.dataStale,
            onTap: _open,
            onMove: (oldIndex, newIndex) =>
                setState(() => _state.move(oldIndex, newIndex)),
          ),
          Expanded(
            child: Container(
              color: T.slot,
              height: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              // 卡片 ≤ 9 张，全量构建：懒加载会让屏幕外的卡没有 context，
              // ensureVisible 就滚不过去
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < ordered.length; i++)
                      KeyedSubtree(
                        key: _keyFor(ordered[i]),
                        child: ModuleCard(
                          store: store,
                          m: ordered[i],
                          index: _state.numberOf(ordered[i].identity),
                          open: _state.isOpen(ordered[i].identity),
                          selected: _state.selected == ordered[i].identity,
                          onToggle: () => _toggle(ordered[i]),
                          onSelect: () => _select(ordered[i]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, String tip) {
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 400),
      child: Pressable(
        onPressed: onTap,
        builder: (c, st) => SizedBox(
          width: 18,
          height: 18,
          child: Icon(icon, size: 14, color: st.hovered ? T.accent : T.text3),
        ),
      ),
    );
  }
}
