import 'package:flutter/cupertino.dart';
import 'package:flutter_opengl/flutter_opengl.dart';

import 'game_menu/game_menu.dart';

void main() {
  OpenGLController().initializeGL();
  runApp(const CupertinoApp(home: GameMenu()));
}
