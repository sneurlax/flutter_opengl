import 'opengl_backend.dart';

class OpenGLController {
  static OpenGLController? _instance;

  factory OpenGLController() => _instance ??= OpenGLController._();

  OpenGLController._();

  OpenGLBackend get openglFFI =>
      throw UnsupportedError('OpenGLController is not supported on this platform.');

  void initializeGL() {
    throw UnsupportedError('OpenGLController is not supported on this platform.');
  }
}
