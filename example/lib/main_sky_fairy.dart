import 'package:flutter/cupertino.dart';
import 'package:glow/glow.dart';

import 'game_menu/game_menu.dart';

void main() {
  OpenGLController().initializeGL();
  runApp(const CupertinoApp(home: GameMenu()));
}
