import 'package:flutter/material.dart';

import 'opengl_controller_web.dart';
import 'opengl_enums.dart';

class OpenGLTexture extends StatelessWidget {
  final int id;

  const OpenGLTexture({
    super.key,
    required this.id,
  });

  @override
  Widget build(BuildContext context) {
    Size twSize = Size.zero;
    Offset startingPos = Offset.zero;

    final controller = OpenGLController();
    final viewType = controller.webBackend.viewType;

    return Listener(
      onPointerDown: (event) {
        startingPos = event.localPosition;
        controller.openglFFI.setMousePosition(
          startingPos,
          event.localPosition,
          PointerEventType.onPointerDown,
          twSize,
        );
      },
      onPointerMove: (event) {
        controller.openglFFI.setMousePosition(
          startingPos,
          event.localPosition,
          PointerEventType.onPointerMove,
          twSize,
        );
      },
      onPointerUp: (event) {
        controller.openglFFI.setMousePosition(
          startingPos,
          event.localPosition,
          PointerEventType.onPointerUp,
          twSize,
        );
      },
      child: LayoutBuilder(builder: (_, __) {
        WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
          final box = context.findRenderObject() as RenderBox;
          twSize = box.size;
        });

        return ColoredBox(
          color: Colors.black,
          child: HtmlElementView(viewType: viewType),
        );
      }),
    );
  }
}
