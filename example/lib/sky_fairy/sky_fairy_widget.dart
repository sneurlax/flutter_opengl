import 'package:flutter/cupertino.dart';
import 'package:flutter_opengl/flutter_opengl.dart';

import 'sky_fairy_game.dart';
import 'sky_fairy_shader.dart';

class SkyFairyWidget extends StatefulWidget {
  const SkyFairyWidget({super.key});

  @override
  State<SkyFairyWidget> createState() => _SkyFairyWidgetState();
}

class _SkyFairyWidgetState extends State<SkyFairyWidget>
    with SingleTickerProviderStateMixin {
  static const int _texW = 400;
  static const int _texH = 300;

  SkyFairyGame? _game;
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

    final err = ffi.setShaderToy(skyFairyShader);
    if (err.isNotEmpty) {
      debugPrint('Sky Fairy shader error: $err');
    }

    // Register custom uniforms
    final zero = [0.0, 0.0, 0.0, 0.0];
    ffi.addVec4Uniform('uGame', zero);
    ffi.addVec4Uniform('uRock0', zero);
    ffi.addVec4Uniform('uRock1', zero);
    ffi.addVec4Uniform('uRock2', zero);
    ffi.addVec4Uniform('uRock3', zero);

    _game = SkyFairyGame(this, ffi);

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
          onTap: () => _game?.tap(),
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
