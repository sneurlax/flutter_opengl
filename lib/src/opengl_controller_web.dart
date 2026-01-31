import 'opengl_backend.dart';
import 'opengl_backend_wasm.dart';

class OpenGLController {
  static OpenGLController? _instance;

  factory OpenGLController() => _instance ??= OpenGLController._();

  OpenGLController._();

  late final OpenGLBackend openglFFI;

  final WasmBackend _wasmBackend = WasmBackend();

  void initializeGL() {
    openglFFI = _wasmBackend;
  }

  WasmBackend get webBackend => _wasmBackend;
}
