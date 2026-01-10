import 'opengl_backend.dart';
import 'opengl_backend_web.dart';

class OpenGLController {
  static OpenGLController? _instance;

  factory OpenGLController() => _instance ??= OpenGLController._();

  OpenGLController._();

  late final OpenGLBackend openglFFI;

  final WebGLBackend _webBackend = WebGLBackend();

  void initializeGL() {
    openglFFI = _webBackend;
  }

  WebGLBackend get webBackend => _webBackend;
}
