import 'package:flutter/widgets.dart';

class GameEntry {
  const GameEntry({required this.name, required this.buildWidget});

  final String name;
  final Widget Function(BuildContext context) buildWidget;
}
