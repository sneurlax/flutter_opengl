import 'package:flutter/cupertino.dart';
import 'package:flutter_opengl/flutter_opengl.dart';

import 'memory_game.dart';
import 'memory_shader.dart';

class MemoryWidget extends StatefulWidget {
  const MemoryWidget({super.key});

  @override
  State<MemoryWidget> createState() => _MemoryWidgetState();
}

class _MemoryWidgetState extends State<MemoryWidget>
    with SingleTickerProviderStateMixin {
  static const int _texW = 400;
  static const int _texH = 400;

  final GlobalKey _boxKey = GlobalKey();
  MemoryGame? _game;
  int _textureId = -1;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ffi = OpenGLController().openglFFI;

    final id = await ffi.createSurface(_texW, _texH);
    if (!mounted) return;

    ffi.startThread();

    final err = ffi.setShaderToy(memoryGameShader);
    if (err.isNotEmpty) {
      debugPrint('Memory Game shader error: $err');
    }

    final zero = [0.0, 0.0, 0.0, 0.0];
    ffi.addVec4Uniform('uGame', zero);
    ffi.addVec4Uniform('uGrid', zero);
    ffi.addVec4Uniform('uAnim', zero);
    ffi.addVec4Uniform('uStates', zero);
    ffi.addVec4Uniform('uSyms0', zero);
    ffi.addVec4Uniform('uTouch', zero);

    _game = MemoryGame(this, ffi);

    setState(() {
      _textureId = id;
      _initialized = true;
    });
  }

  @override
  void dispose() {
    _game?.dispose();
    OpenGLController().openglFFI.stopThread();
    super.dispose();
  }

  Size _widgetSize() {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) return box.size;
    return Size(_texW.toDouble(), _texH.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _textureId == -1) {
      return const Center(child: CupertinoActivityIndicator());
    }

    return Container(
      color: const Color(0xFF000000),
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final game = _game;
            if (game == null) return;
            final size = _widgetSize();
            final lx = details.localPosition.dx;
            final ly = details.localPosition.dy;
            game.setTouch(lx / size.width, ly / size.height);
            final idx = game.cardIndexFromPosition(
                lx, ly, size.width, size.height);
            if (idx >= 0) game.tapCard(idx);
          },
          child: SizedBox(
            key: _boxKey,
            width: _texW.toDouble(),
            height: _texH.toDouble(),
            child: OpenGLTexture(id: _textureId),
          ),
        ),
      ),
    );
  }
}
