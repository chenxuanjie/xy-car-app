import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/tokens.dart';

/// 连接对话框：可改地址、记住最近、明确显示当前状态与失败原因
class ConnectDialog extends StatefulWidget {
  const ConnectDialog({super.key, required this.store});
  final Store store;

  @override
  State<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<ConnectDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.store.endpoint);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _valid(String s) {
    final u = Uri.tryParse(s.trim());
    return u != null &&
        (u.scheme == 'ws' || u.scheme == 'wss') &&
        u.host.isNotEmpty;
  }

  void _connect() {
    final url = _ctrl.text.trim();
    if (!_valid(url)) {
      setState(() {});
      return;
    }
    widget.store.connect(url);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final ok = _valid(_ctrl.text);
    final linked = s.link == Link.connected;
    return Dialog(
      backgroundColor: T.panel,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: T.hair),
        borderRadius: BorderRadius.zero,
      ),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '连接 / LINK',
                    style: sans(15, T.text1, w: FontWeight.w600, ls: 0.6),
                  ),
                  const Spacer(),
                  Text(
                    linked
                        ? '已连接'
                        : s.link == Link.connecting
                        ? '连接中'
                        : '未连接',
                    style: mono(
                      9.5,
                      linked
                          ? T.ok
                          : s.link == Link.connecting
                          ? T.warn
                          : T.text3,
                      ls: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('后端地址', style: mono(8.5, T.text3, ls: 1.2)),
              const SizedBox(height: 6),
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: T.slot,
                  border: Border.all(color: ok ? T.accentEdge : T.danger),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: _ctrl,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _connect(),
                  cursorColor: T.accent,
                  style: mono(12, T.text1, ls: 0.2),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'ws://127.0.0.1:9999/ws',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ok ? 'ws:// 或 wss://，回车直接连接' : '地址无效：需要 ws:// 或 wss:// 开头且带主机名',
                style: sans(9.5, ok ? T.text3 : T.danger),
              ),
              if (s.recentUrls.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('最近使用', style: mono(8.5, T.text3, ls: 1.2)),
                const SizedBox(height: 6),
                for (final u in s.recentUrls.take(4))
                  GestureDetector(
                    onTap: () => setState(() => _ctrl.text = u),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(u, style: mono(10.5, T.text2, ls: 0.2)),
                    ),
                  ),
              ],
              if (s.linkError != null) ...[
                const SizedBox(height: 12),
                Text(
                  '上次错误：${s.linkError!}',
                  style: sans(9.5, T.danger),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (linked)
                    TextButton(
                      onPressed: () {
                        widget.store.disconnect();
                        Navigator.pop(context);
                      },
                      child: Text('断开', style: sans(12, T.warn)),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('取消', style: sans(12, T.text2)),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: ok ? _connect : null,
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      color: ok ? T.accent : T.hair,
                      alignment: Alignment.center,
                      child: Text(
                        linked ? '重新连接' : '连接',
                        style: sans(
                          12.5,
                          ok ? T.onAccent : T.text3,
                          w: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
