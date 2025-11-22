import 'flutter_opengl.dart';
import 'flutter_opengl_web.dart';
import 'opengl_backend.dart';
import 'opengl_backend_web.dart';

class OpenGLController {
  static OpenGLController? _instance;

  factory OpenGLController() => _instance ??= OpenGLController._();

  OpenGLController._();

  late final FlutterOpengl openglPlugin;
  late final OpenGLBackend openglFFI;

  final WebGLBackend _webBackend = WebGLBackend();

  initializeGL() {
    openglFFI = _webBackend;
    openglPlugin = FlutterOpengl();

    FlutterOpenglWeb.setBackend(_webBackend);
  }

  WebGLBackend get webBackend => _webBackend;
}
