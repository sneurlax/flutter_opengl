import 'package:flutter/cupertino.dart';
import 'package:glow/glow.dart';

import 'minesweeper_game.dart';
import 'minesweeper_shader.dart';

class MinesweeperWidget extends StatefulWidget {
  const MinesweeperWidget({super.key});

  @override
  State<MinesweeperWidget> createState() => _MinesweeperWidgetState();
}

class _MinesweeperWidgetState extends State<MinesweeperWidget>
    with SingleTickerProviderStateMixin {
  static const int _texW = 400;
  static const int _texH = 400;

  MinesweeperGame? _game;
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

    final err = ffi.setShaderToy(minesweeperShader);
    if (err.isNotEmpty) {
      debugPrint('Minesweeper shader error: $err');
    }

    final zero = [0.0, 0.0, 0.0, 0.0];
    ffi.addVec4Uniform('uGame', zero);
    for (int i = 0; i < 10; i++) {
      ffi.addVec4Uniform('uRow$i', zero);
    }
    ffi.addVec4Uniform('uHighlight', zero);

    _game = MinesweeperGame(this, ffi);

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

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _textureId == -1) {
      return const Center(child: CupertinoActivityIndicator());
    }

    return Container(
      color: const Color(0xFF000000),
      child: Center(
        child: GestureDetector(
          onTapUp: (details) {
            final game = _game;
            if (game == null) return;
            final cell = game.cellFromPosition(
                details.localPosition.dx,
                details.localPosition.dy,
                _texW.toDouble(),
                _texH.toDouble());
            if (cell[0] >= 0) game.reveal(cell[1], cell[0]);
          },
          onLongPressStart: (details) {
            final game = _game;
            if (game == null) return;
            final cell = game.cellFromPosition(
                details.localPosition.dx,
                details.localPosition.dy,
                _texW.toDouble(),
                _texH.toDouble());
            if (cell[0] >= 0) game.toggleFlag(cell[1], cell[0]);
          },
          child: SizedBox(
            width: _texW.toDouble(),
            height: _texH.toDouble(),
            child: OpenGLTexture(id: _textureId),
          ),
        ),
      ),
    );
  }
}
