import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../theme/type.dart';
import 'card_state.dart';
import 'controls.dart';
import 'px.dart';

String roleLabel(ModuleVm m) {
  if (m.runtime.manualChannel) return '自定义通道';
  switch (m.role) {
    case 'chassis_drive':
      return '麦轮驱动x4';
    case 'imu':
      return 'IMU 姿态';
    case 'lidar_proxy':
      return '激光雷达';
    case 'gimbal':
      return '云台';
  }
  return '自定义模块';
}

/// 单张模块卡：无状态，只吃 props 和回调
class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.store,
    required this.m,
    required this.index,
    required this.open,
    required this.selected,
    required this.onToggle,
    required this.onSelect,
  });

  final Store store;
  final ModuleVm m;
  final int index;
  final bool open;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final spec = deriveCard(m);
    final stale = store.dataStale;
    final died = m.runtime.bindState == 'OFFLINE';
    final canWrite = spec.access == kAccessFullWrite && !stale && !died;
    final canSome =
        (spec.access == kAccessFullWrite || spec.access == kAccessPartial) &&
        !stale &&
        !died;
    // 蓝条：只有"选中且展开"的卡才有，覆盖整张卡（含窗头）
    final hl = open && selected;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: died ? T.slot : (open ? T.raised2 : T.raised),
          border: Border.all(
            width: hairline(),
            color: died ? T.hairSoft : (open ? T.accentEdge : T.hairSoft),
          ),
        ),
        foregroundDecoration: hl
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(width: 2, color: stale ? T.text3 : T.accent),
                ),
              )
            : null,
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: SizedBox(
                height: 38,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _indexChip(m, index, died || stale),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          roleLabel(m),
                          overflow: TextOverflow.ellipsis,
                          style: sans(TS.value, died ? T.text3 : T.text1),
                        ),
                      ),
                      Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: T.text3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (open) _controls(canWrite, canSome),
          ],
        ),
      ),
    );
  }

  Widget _indexChip(ModuleVm m, int index, bool faded) {
    final health = m.runtime.health;
    final c = Color(chipColor(health));
    final weak = health == 'degraded';
    final alphaBorder = faded ? 0.22 : (weak ? 0.45 : 0.8);
    final alphaFill = faded ? 0.03 : (weak ? 0.06 : 0.12);
    return Container(
      width: 30,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: alphaFill),
        border: Border.all(color: c.withValues(alpha: alphaBorder)),
      ),
      child: Text(
        m.runtime.manualChannel ? 'CH' : 'M${index.toString().padLeft(2, '0')}',
        style: mono(TS.micro, faded ? T.text3 : c, ls: 0.9),
      ),
    );
  }

  Widget _controls(bool canWrite, bool canSome) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF15191E),
        border: Border(
          top: BorderSide(color: T.hairSoft, width: hairline()),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScalarControl(
            label: '目标速度',
            unit: 'm/s',
            value: store.motion.v,
            min: -1.2,
            max: 1.2,
            enabled: canWrite,
            liveHz: 20,
            onLive: (val) => store.send(
              'set_speed',
              {
                'module_identity': m.identity,
                'value': double.parse(val.toStringAsFixed(2)),
              },
              track: false,
              logTx: false,
            ),
            onCommit: (val) => store.send('set_speed', {
              'module_identity': m.identity,
              'value': double.parse(val.toStringAsFixed(2)),
            }),
          ),
          const SizedBox(height: 10),
          ToggleControl(
            store: store,
            identity: m.identity,
            label: '使能 / ENABLE',
            value: m.runtime.bindState == 'ACTIVE',
            enabled: canSome,
          ),
          const SizedBox(height: 6),
          TelemetryRow(
            label: '轮速 LF',
            value: store.motion.rpm.isNotEmpty
                ? store.motion.rpm[0].toString()
                : '—',
            unit: 'rpm',
            stale: store.dataStale || store.motionAgeMs > 100,
          ),
          TelemetryRow(label: '固件', value: m.fwVer, unit: 'p${m.protoVer}'),
        ],
      ),
    );
  }
}
