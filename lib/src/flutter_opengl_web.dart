import 'dart:ui_web' as ui_web;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'flutter_opengl_platform_interface.dart';
import 'opengl_backend_web.dart';

class FlutterOpenglWeb extends FlutterOpenglPlatform {
  static WebGLBackend? _backend;

  FlutterOpenglWeb();

  /// Called by Flutter's auto-generated web plugin registrant.
  static void registerWith(Registrar registrar) {
    FlutterOpenglPlatform.instance = FlutterOpenglWeb();
  }

  /// Called by [OpenGLController] to wire up the WebGL backend.
  static void setBackend(WebGLBackend backend) {
    _backend = backend;
  }

  @override
  Future<int> createSurface(int width, int height) async {
    final backend = _backend;
    if (backend == null) {
      throw StateError(
          'WebGLBackend not initialized. Call OpenGLController().initializeGL() first.');
    }

    final canvas = backend.createCanvas(width, height);

    ui_web.platformViewRegistry.registerViewFactory(
      backend.viewType,
      (int viewId, {Object? params}) => canvas,
    );

    return 0; // dummy texture ID; web uses HtmlElementView
  }
}
