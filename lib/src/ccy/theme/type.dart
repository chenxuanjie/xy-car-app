import 'tokens_gen.dart';

/// 字号阶梯。
///
/// 设计包只给了 4 档（caption 11 / body 13 / title 15 / display 28），
/// 那是"文档/卡片"的尺度；仪表盘还需要两档更小的读数与编号，由本工程补充，
/// 但要和那 4 档排在同一条等比线上（8.5 → 9.5 → 11 → 12 → 13 → 15）。
class TS {
  /// 编号、单位、微标注
  static const double micro = 8.5;

  /// 顶栏胶囊、页签
  static const double label = 9.5;

  /// 说明 / 标签（设计 token）
  static const double caption = TokScale.TypeCaptionSize;

  /// 仪表读数（比 body 略小，给数字留紧凑感）
  static const double value = 13;

  /// 正文（设计 token）
  static const double body = TokScale.TypeBodySize;

  /// 标题（设计 token）
  static const double title = TokScale.TypeTitleSize;

  /// 大数展示（设计 token）
  static const double display = TokScale.TypeDisplaySize;
}
