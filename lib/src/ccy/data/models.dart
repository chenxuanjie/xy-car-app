class RuntimeVm {
  RuntimeVm({
    required this.bindState,
    required this.transport,
    required this.owner,
    required this.health,
    this.leaseTtlMs,
    this.faultCode,
    this.manualChannel = false,
    this.calibrating = false,
    this.iapActive = false,
    this.lastSeenMs,
    this.conflictReason,
  });

  final String bindState;
  final String transport;
  final String owner;
  final String health;
  final int? leaseTtlMs;
  final int? faultCode;
  final bool manualChannel;
  final bool calibrating;
  final bool iapActive;
  final int? lastSeenMs;
  final String? conflictReason;

  static RuntimeVm fromJson(Map<String, dynamic> j) {
    final conflict = j['conflict'];
    return RuntimeVm(
      bindState: j['bind_state'] as String? ?? 'UNSEEN',
      transport: j['transport'] as String? ?? 'USB',
      owner: j['control_owner'] as String? ?? 'None',
      health: j['health'] as String? ?? 'ok',
      leaseTtlMs: (j['lease_ttl_ms'] as num?)?.toInt(),
      faultCode: (j['fault_code'] as num?)?.toInt(),
      manualChannel: j['manual_channel'] == true,
      calibrating: j['calibrating'] == true,
      iapActive: j['iap_active'] == true,
      lastSeenMs: (j['last_seen_ms'] as num?)?.toInt(),
      conflictReason: conflict is Map ? conflict['reason'] as String? : null,
    );
  }
}

class ModuleVm {
  ModuleVm({
    required this.identity,
    required this.type,
    required this.role,
    required this.vendor,
    required this.model,
    required this.fwVer,
    required this.protoVer,
    required this.nodeCount,
    required this.powerProfile,
    required this.kinematicTag,
    required this.capabilityFlags,
    required this.features,
    required this.runtime,
  });

  final String identity;
  final String type;
  final String role;
  final String vendor;
  final String model;
  final String fwVer;
  final int protoVer;
  final int nodeCount;
  final String powerProfile;
  final String kinematicTag;
  final int capabilityFlags;
  final List<String> features;
  final RuntimeVm runtime;

  bool get hasActuator => features.contains('move');

  /// 导航列里的短标签：自定义通道 -> 自定义，其余取 M+序号
  String get navLabel {
    if (runtime.manualChannel) return '自定义';
    final parts = identity.split('-');
    final tail = parts.isEmpty ? identity : parts.last;
    return 'M$tail';
  }

  static ModuleVm fromJson(Map<String, dynamic> j) {
    final rt = (j['runtime'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ModuleVm(
      identity: j['module_identity'] as String? ?? '?',
      type: j['module_type'] as String? ?? 'custom',
      role: j['module_role'] as String? ?? 'custom',
      vendor: j['vendor'] as String? ?? '-',
      model: j['model'] as String? ?? '-',
      fwVer: j['fw_ver'] as String? ?? '-',
      protoVer: (j['proto_ver'] as num?)?.toInt() ?? 0,
      nodeCount: (j['node_count'] as num?)?.toInt() ?? 0,
      powerProfile: j['power_profile'] as String? ?? 'need_5v',
      kinematicTag: j['kinematic_tag'] as String? ?? 'none',
      capabilityFlags: (j['capability_flags'] as num?)?.toInt() ?? 0,
      features: (j['features'] as List?)?.cast<String>() ?? const [],
      runtime: RuntimeVm.fromJson(rt),
    );
  }
}
