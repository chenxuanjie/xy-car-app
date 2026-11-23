part of '../../main.dart';

String _stationDataError(Object error, _Translate tr) {
  if (error is AppClientFailure) {
    if (error.status == 401) {
      return tr('请先在设置中登录账号', 'Sign in from Settings to use account storage.');
    }
    if (error.code == 'invalid_device' || error.status == 422) {
      return tr(
        '请检查名称、地址、端口或航点',
        'Check the name, address, port or waypoints.',
      );
    }
    if (error.code == 'invalid_mission_name') {
      return tr(
        '请输入任务名称，最多 80 个字符',
        'Enter a mission name of up to 80 characters.',
      );
    }
    if (error.code == 'too_many_waypoints') {
      return tr(
        '每个存档最多保存 256 个航点',
        'A saved mission can contain up to 256 waypoints.',
      );
    }
    if (error.code == 'mission_not_found') {
      return tr('未找到任务存档', 'Saved mission not found.');
    }
  }
  return tr('账号存档暂不可用，请重试', 'Account storage is unavailable. Try again.');
}

class _MissionArchive extends StatefulWidget {
  const _MissionArchive({
    required this.tr,
    required this.client,
    required this.current,
  });

  final _Translate tr;
  final StationDataClient client;
  final StationMission current;

  @override
  State<_MissionArchive> createState() => _MissionArchiveState();
}

class _MissionArchiveState extends State<_MissionArchive> {
  late final _name = TextEditingController(text: widget.current.name);
  final _names = <String>[];
  String? _next;
  String? _notice;
  bool _working = false;
  bool _listed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_list());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _notice = _stationDataError(error, widget.tr));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _list({bool more = false}) => _run(() async {
    final page = await widget.client.listMissions(after: more ? _next : null);
    if (!mounted) return;
    setState(() {
      if (!more) _names.clear();
      _names.addAll(page.names);
      _next = page.next;
      _listed = true;
    });
  });

  Future<void> _load(String name) => _run(() async {
    final mission = await widget.client.readMission(name);
    if (mounted) {
      Navigator.pop(context, mission);
    }
  });

  Future<void> _save() => _run(() async {
    final mission = await widget.client.saveMission((
      name: _name.text.trim(),
      waypoints: widget.current.waypoints,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.tr('任务已保存', 'Mission saved'))),
    );
    Navigator.pop(context, mission);
  });

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    return AlertDialog(
      backgroundColor: _surface,
      title: Text(tr('任务存档', 'Saved missions')),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                enabled: !_working,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: tr('任务名称', 'Mission name'),
                  helperText: tr(
                    '同名保存会更新已有存档',
                    'Saving under the same name updates it.',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const Divider(),
              if (_working) const LinearProgressIndicator(),
              if (_notice case final text?) Text(text),
              if (!_listed && !_working)
                TextButton(
                  onPressed: _list,
                  child: Text(tr('重试读取列表', 'Retry loading missions')),
                ),
              if (_listed && _names.isEmpty)
                Text(tr('账号下暂无任务存档', 'No missions saved yet.')),
              if (_names.isNotEmpty)
                Text(
                  tr(
                    '选择存档会替换当前航点',
                    'Loading a mission replaces the current waypoints.',
                  ),
                ),
              for (final name in _names)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(name),
                  trailing: const Icon(Icons.download_outlined),
                  onTap: _working ? null : () => _load(name),
                ),
              if (_next != null)
                TextButton(
                  onPressed: _working ? null : () => _list(more: true),
                  child: Text(tr('加载更多', 'Load more')),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('关闭', 'Close')),
        ),
        FilledButton(
          onPressed: _working ? null : _save,
          child: Text(tr('保存当前航点', 'Save current waypoints')),
        ),
      ],
    );
  }
}
