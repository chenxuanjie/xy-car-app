/// 模块窗的展开 / 选中状态。
///
/// 纯 Dart，不依赖 Flutter，可以单测——所有"展开与选中互相打架"的回归
/// 都出在这三个状态的交互上，所以把它们从 widget 里抽出来。
class ModuleListState {
  ModuleListState({this.autoOpenFirst = true});

  /// 首屏是否自动展开第一张（用户一旦操作过就不再自动）
  final bool autoOpenFirst;

  /// 当前模块 id 列表（由外部同步进来）
  List<String> ids = const [];

  final Set<String> _expanded = <String>{};
  bool _touched = false;

  String? selected;

  bool get touched => _touched;

  bool isOpen(String id) {
    if (_touched) return _expanded.contains(id);
    return autoOpenFirst && ids.isNotEmpty && id == ids.first;
  }

  bool get anyOpen =>
      _touched ? _expanded.isNotEmpty : (autoOpenFirst && ids.isNotEmpty);

  /// 把"自动展开的第一张"落成真实状态。
  /// 不做这一步，用户点第二张时第一张会凭空消失。
  void seed() {
    if (_touched) return;
    _touched = true;
    if (autoOpenFirst && ids.isNotEmpty) _expanded.add(ids.first);
  }

  /// 点窗头：切换展开，同时选中
  void toggle(String id) {
    seed();
    if (!_expanded.remove(id)) _expanded.add(id);
    selected = id;
  }

  /// 点导航：展开 + 选中，不收起其他卡
  void openOnly(String id) {
    seed();
    _expanded.add(id);
    selected = id;
  }

  /// 点卡片空白：只选中，不动展开
  void select(String id) => selected = id;

  void expandAll() {
    seed();
    _expanded.addAll(ids);
  }

  void collapseAll() {
    _touched = true;
    _expanded.clear();
  }

  /// 用户自定义顺序（identity 列表）。长按导航排序时维护。
  List<String> order = const [];

  /// 稳定编号：模块第一次出现时分配，之后排序 / 增减都不变
  final Map<String, int> _num = <String, int>{};

  int numberOf(String id) => _num[id] ?? 0;

  /// 把 store 的模块列表同步进来：保留已有顺序，新增的追加到末尾，消失的剔除
  void syncModules(List<String> incoming) {
    if (order.isEmpty) {
      order = List<String>.from(incoming);
      ids = order;
      _assignNumbers(incoming);
      return;
    }
    final kept = order.where(incoming.contains).toList();
    for (final id in incoming) {
      if (!kept.contains(id)) kept.add(id);
    }
    order = kept;
    ids = kept;
    _assignNumbers(incoming);
  }

  void _assignNumbers(List<String> incoming) {
    var next = _num.length;
    for (final id in incoming) {
      if (!_num.containsKey(id)) _num[id] = ++next;
    }
  }

  /// 长按拖拽结束后提交新顺序
  void move(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= order.length) return;
    if (newIndex < 0 || newIndex > order.length) return;
    // 导航组件已把目标位置换算为移除旧位置后的索引。
    final next = List<String>.from(order);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    order = next;
    ids = next;
  }
}
