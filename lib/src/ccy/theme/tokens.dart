import 'package:flutter/material.dart';

import 'tokens_gen.dart';

export 'tokens_gen.dart';

/// 语义别名层。
///
/// 颜色/尺度的唯一来源是 tokens_gen.dart（由设计包 tokens.json 生成）。
/// 这里只做两件事：
///   1. 把设计 token 名映射成工程里在用的短名（T.bg / T.hair …）；
///   2. 定义少量派生色（设计稿用 box-shadow / rgba 现场算的，不是独立 token）。
///
/// 改动纪律：颜色和间距不要在这里手写值，去改设计包再重新生成。
class T {
  // ---- 面板与背景 ----
  // 采用设计稿 play 模式的石墨冷调（play.css 对 --canvas/--panel/... 的覆盖）
  static const Color bg = Color(0xFF090B0E);
  static const Color desk = Color(0xFF06080A);
  static const Color panel = Color(0xFF111519);
  static const Color raised = Color(0xFF191E24);

  /// 派生：展开卡（panel-raised 再亮一档）
  static const Color raised2 = Color(0xFF1F252C);

  /// 派生：模块窗底槽（比 canvas 更深一档）
  static const Color slot = Color(0xFF0B0E12);

  static const Color grid = Color(0xFF141A1F);
  static const Color hair = Color(0xFF222A31);

  /// 派生：hairline 的弱化版（8% 白），用于行分隔
  static const Color hairSoft = Color(0x14FFFFFF);

  /// 派生：视觉环（20% 白）
  static const Color ring = Color(0x33FFFFFF);

  // ---- 文字 ----
  static const Color text1 = Color(0xFFEAF1F7);
  static const Color text2 = Color(0xFF93A1AE);
  static const Color text3 = Color(0xFF59636F);

  // ---- 语义色 ----
  static const Color accent = TokDark.Accent;
  static const Color accentDim = TokDark.AccentDim;
  static const Color onAccent = TokDark.OnAccent;

  /// 派生：accent 32% —— 描边用，不是独立 token
  static const Color accentEdge = Color(0x524FB6FF);

  static const Color ok = TokDark.Ok;
  static const Color warn = TokDark.Warn;
  static const Color danger = TokDark.Danger;

  static const Color accentSoft = TokDark.AccentSoft;
  static const Color okSoft = TokDark.OkSoft;
  static const Color warnSoft = TokDark.WarnSoft;
  static const Color dangerSoft = TokDark.DangerSoft;

  // ---- 间距（来自 scale.spacing） ----
  static const double sp1 = TokScale.S1;
  static const double sp2 = TokScale.S2;
  static const double sp3 = TokScale.S3;
  static const double sp4 = TokScale.S4;
  static const double sp5 = TokScale.S5;
  static const double sp6 = TokScale.S6;

  // ---- 圆角 ----
  static const double radiusBase = TokScale.Rbase;
  static const double radiusCard = TokScale.Rcard;
  static const double radiusFull = TokScale.Rfull;
}

/// 拉丁字形用打包字体（Space Grotesk / JetBrains Mono），中文字形走系统回退。
TextStyle mono(
  double size,
  Color c, {
  double ls = 0.6,
  FontWeight w = FontWeight.w500,
}) {
  return TextStyle(
    fontFamily: 'JetBrainsMono',
    fontFamilyFallback: const ['Consolas', 'Microsoft YaHei', 'SimHei'],
    fontSize: size,
    color: c,
    letterSpacing: ls,
    fontWeight: w,
    height: 1.0,
    decoration: TextDecoration.none,
  );
}

TextStyle sans(
  double size,
  Color c, {
  double ls = 0,
  FontWeight w = FontWeight.w400,
}) {
  return TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontFamilyFallback: const ['Inter', 'Microsoft YaHei', 'SimHei'],
    fontSize: size,
    color: c,
    letterSpacing: ls,
    fontWeight: w,
    height: 1.15,
    decoration: TextDecoration.none,
  );
}
