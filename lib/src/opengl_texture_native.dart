import 'package:flutter/material.dart';

import 'opengl_controller.dart';
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
    var key = GlobalKey();

    return Listener(
      onPointerDown: (event) {
        startingPos = event.localPosition;
        OpenGLController().openglFFI.setMousePosition(
              startingPos,
              event.localPosition,
              PointerEventType.onPointerDown,
              twSize,
            );
      },
      onPointerMove: (event) {
        OpenGLController().openglFFI.setMousePosition(
              startingPos,
              event.localPosition,
              PointerEventType.onPointerMove,
              twSize,
            );
      },
      onPointerUp: (event) {
        OpenGLController().openglFFI.setMousePosition(
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
          key: key,
          color: Colors.black,
          child: Texture(textureId: id),
        );
      }),
    );
  }
}
