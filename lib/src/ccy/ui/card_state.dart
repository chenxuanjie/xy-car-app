import '../data/models.dart';

/// 协议态 -> **权限档位**。唯一真相，不要在 widget 里散落 switch。
/// 注意：这里不再产出卡头文案——界面上不显示状态词（见交互说明书 §2.6）。
class CardSpec {
  const CardSpec(this.state, this.access);
  final String state;

  /// none | readOnly | partial | fullWrite
  final String access;
}

const kAccessNone = 'none';
const kAccessReadOnly = 'readOnly';
const kAccessPartial = 'partial';
const kAccessFullWrite = 'fullWrite';

CardSpec deriveCard(ModuleVm m) {
  final r = m.runtime;
  if (r.bindState == 'OFFLINE') return const CardSpec('offline', kAccessNone);
  if (r.iapActive) return const CardSpec('updating', kAccessReadOnly);
  if (r.bindState == 'QUARANTINE') {
    return const CardSpec('quarantine', kAccessReadOnly);
  }
  if (r.conflictReason != null) {
    return const CardSpec('conflict', kAccessPartial);
  }
  if (r.calibrating) return const CardSpec('calibrating', kAccessPartial);
  if (r.manualChannel) return const CardSpec('manual', kAccessFullWrite);
  switch (r.bindState) {
    case 'UNSEEN':
      return const CardSpec('empty', kAccessNone);
    case 'DETECTED':
    case 'IDENTIFIED':
      return const CardSpec('standby', kAccessPartial);
    case 'ACTIVE':
      return const CardSpec('live', kAccessFullWrite);
    case 'BOUND':
      return m.hasActuator
          ? const CardSpec('standby', kAccessPartial)
          : const CardSpec('ok', kAccessReadOnly);
    case 'DEGRADED':
    case 'SAFE_FALLBACK':
      return const CardSpec('standby', kAccessPartial);
  }
  return const CardSpec('empty', kAccessNone);
}

/// 编号框颜色 = 模块健康状态（不再单独放 4px 点）
/// 正常用天蓝而不是绿：整个界面的"正常"语义由 accent 承担，绿色只留给数值本身。
int chipColor(String health) {
  switch (health) {
    case 'ok':
      return 0xFF4FB6FF; // accent
    case 'warn':
      return 0xFFFFB020;
    case 'degraded':
      return 0xFFFFB020; // 同 warn，但用更低的透明度区分（见 mods_window）
    case 'fault':
      return 0xFFFF4D5F;
  }
  return 0xFF5C6671;
}
