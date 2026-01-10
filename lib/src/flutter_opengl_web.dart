import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web plugin registrant.
///
/// Flutter's build system calls [registerWith] automatically on web.
/// This class is referenced in pubspec.yaml under `flutter: plugin: platforms: web:`.
class FlutterOpenglWeb {
  FlutterOpenglWeb._();

  /// Called by Flutter's auto-generated web plugin registrant.
  static void registerWith(Registrar registrar) {
    // No-op: all web initialisation happens in OpenGLController / WebGLBackend.
  }
}
