import 'dart:math' as math;
import 'dart:ui' show Rect;

/// 画布缩放与设备像素比：由 AppShell 在 build 时写入，绘制时读取。
/// 目的只有一件事：**让 1px 线永远落在整数个物理像素上**。
double gCanvasScale = 1.0;
double gDpr = 1.0;

/// 设计稿坐标系下的线宽：**恒等于 1 个物理像素**。
///
/// 物理像素 = 设计值 × gCanvasScale × gDpr。反解出设计值，线就永远
/// 是一整行/整列实心，永远不发灰、不摊成两行。
/// 例：scale 1.514、dpr 1.0 → 设计值 0.660 → 物理 1.0
///     scale 0.889、dpr 1.5 → 设计值 0.750 → 物理 1.0
double hairline() {
  final raw = gCanvasScale * gDpr;
  if (raw <= 0) return 1;
  return 1.0 / raw;
}

/// 面板描边要"内对齐"：路径内缩半个线宽，描边才正好落在整数物理像素上。
double hairlineInset() => hairline() / 2;

/// 画布缩放上限：再大就只是把界面吹大，线条相对越来越细，没有意义。
const double kMaxCanvasScale = 1.6;
const double kMinCanvasScale = 0.889;

double canvasScaleFor(
  double w,
  double h, {
  double designW = 1440,
  double designH = 900,
}) {
  final raw = math.min(w / designW, h / designH);
  return raw.clamp(kMinCanvasScale, kMaxCanvasScale);
}

/// 画布宽上限：再宽面板也不会变大，多出的部分交给图传出血
const double kMaxCanvasWidth = 1920;
const double kMinCanvasWidth = 1440;

/// 画布宽度（设计单位）：有界流体。
///
/// - 窗口比 16:10 宽 → 画布变宽（多出的宽度给图传）
/// - 超过 1920 → 封顶，剩余交给图传出血
/// - 下限恒为 1440：窗口再窄，画布也不缩，只裁内容
double canvasWidthFor(double w, double h, {double designH = 900}) {
  final s = canvasScaleFor(w, h, designH: designH);
  if (s <= 0) return kMinCanvasWidth;
  return (w / s).clamp(kMinCanvasWidth, kMaxCanvasWidth);
}

/// 图传在 play 模式下要铺满整个窗口，可以超出画布边界。
/// 返回设计坐标系里的矩形（相对画布左上角，可能为负）。
Rect videoBleedRect(
  double w,
  double h,
  double canvasW, {
  double designH = 900,
}) {
  final s = canvasScaleFor(w, h, designH: designH);
  if (s <= 0) return Rect.fromLTWH(0, 0, canvasW, designH);
  final vw = w / s;
  final vh = h / s;
  return Rect.fromLTWH(-(vw - canvasW) / 2, -(vh - designH) / 2, vw, vh);
}

/// 画布高度（设计单位）：高度不足时用 900，窗口更高就跟着长。
/// 否则竖屏时底部一大片不属于画布，浮窗永远够不到窗口底部。
double canvasHeightFor(double w, double h, {double designH = 900}) {
  final s = canvasScaleFor(w, h, designH: designH);
  if (s <= 0) return designH;
  return math.max(designH, h / s);
}
