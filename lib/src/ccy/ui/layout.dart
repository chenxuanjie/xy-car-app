/// 所有布局常量集中在这里（画布、边距、窗口尺寸、监控栅格）。
/// 单窗口的坐标不要再写死在 widget 里。
class L {
  // 画布
  static const double canvasW = 1440;
  static const double canvasH = 900;

  // 通用间距
  static const double margin = 20;
  static const double gap = 12;
  static const double topBarH = 42;

  // play：浮窗
  static const double modsW = 336;
  static const double modsH = 670;
  static const double modsTop = 78;
  static const double infoW = 320;
  static const double infoTop = 78;
  static const double infoRight = 20;
  static const double genLeft = 20;
  static const double genBottom = 12;
  static const double genDefaultW = 1400;
  static const double genDefaultH = 128;

  // monitor：栅格
  static const double monPad = 12;
  static const double monMainTop = 68;
  static const double monMainH = 820;
  static const double monModsW = 330;
  static const double monModsH = 820;
  static const double monInfoW = 322;
  static const double monInfoLeft = 1106;
  static const double monGenLeft = 354;
  static const double monGenW = 1074;
  static const double monGenBottom = 12;

  static double get monRowH => monMainH; // 视频 + 通用窗合计高度
}
