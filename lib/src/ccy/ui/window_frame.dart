import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'kit.dart';

/// 三扇窗共用的外壳：切角面板 + 头条 + 内容区 + 可叠加的手柄层。
/// 统一尺寸语义与描边，避免每个窗口各写一遍 Stack/Column。
class WindowFrame extends StatelessWidget {
  const WindowFrame({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.title,
    this.header,
    this.trailing,
    this.dimmed = false,
    this.fill = T.panel,
    this.glass = false,
    this.overlay = const <Widget>[],
  });

  final double width;
  final double height;
  final Widget child;

  /// 用默认头条（PanelHead）时给标题
  final String? title;

  /// 自定义头条（例如通用窗的页签栏）
  final Widget? header;

  final Widget? trailing;
  final bool dimmed;
  final Color fill;

  /// 浮在图传上的窗用玻璃：78% 面板色（通透，不虚化）+ 16% 白描边
  final bool glass;

  /// 叠加在面板之上、不参与裁剪的东西（缩放手柄等）
  final List<Widget> overlay;

  @override
  Widget build(BuildContext context) {
    final head =
        header ??
        PanelHead(title: title ?? '', dimmed: dimmed, trailing: trailing);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CutPanel(
              fill: glass ? const Color(0xC714171B) : fill,
              stroke: glass ? const Color(0x29EDF1F6) : T.hair,
              // 设计稿是通透玻璃：能看清后面的楼层细节，所以不虚化
              blur: 0,
              child: Column(
                children: [
                  head,
                  Expanded(child: child),
                ],
              ),
            ),
          ),
          ...overlay,
        ],
      ),
    );
  }
}
