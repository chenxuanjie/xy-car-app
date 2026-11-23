/// 所有面向用户的文案集中在这里。
/// 现在先集中（不上 intl）；等要做双语时，把这里换成 ARB 即可，widget 不用动。
class S {
  // 面板标题
  static const modules = '模块 / MODULES';
  static const status = '状态 / STATUS';
  static const alerts = '告警 / ALERTS';
  static const noAlerts = '无告警';
  static const noLogs = '无日志';
  static const noModule = 'no module';

  // 连接
  static const connect = '连接 / LINK';
  static const backendAddr = '后端地址';
  static const recent = '最近使用';
  static const connected = '已连接';
  static const connecting = '连接中';
  static const disconnected = '未连接';
  static const btnConnect = '连接';
  static const btnReconnect = '重新连接';
  static const btnDisconnect = '断开';
  static const btnCancel = '取消';
  static const addrHint = 'ws:// 或 wss://，回车直接连接';
  static const addrInvalid = '地址无效';
  static const lastError = '上次错误：';

  // 控件
  static const targetSpeed = '目标速度';
  static const enable = '使能 / ENABLE';
  static const wheelLf = '轮速 LF';
  static const firmware = '固件';
  static const estop = '急停  E-STOP';
  static const estopClear = '解除急停·按住';

  // 遥测标签
  static const linSpeed = '线速度';
  static const angSpeed = '角速度';
  static const rtt = '链路时延';
  static const loss = '丢包率';

  static String wheelCh(int i) => '轮速 CH${i + 1}';
  static String modulesCount(int n) => '$n / 9';
  static String chCount(int n) => '$n CH';
  static String activeAlerts(int n) => '$n ACTIVE';
  static String lastErr(String e) => lastError + e;

  // 顶栏
  static const toggleInfo = 'INFO';
  static const toggleMods = 'MOD';
  static const toggleGen = 'GEN';
  static const modeMonitor = '监控';
  static const modePlay = '游戏';

  // 页签
  static const tabNow = '现在';
  static const tabLog = '日志';
  static const tabUpgrade = '升级';
  static const tabSettings = '设置';
  static const tabs = [tabNow, tabLog, tabUpgrade, tabSettings];

  // 提示
  static const expandAll = '全部展开';
  static const collapseAll = '全部收起';
}
