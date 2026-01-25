import 'dart:ffi' as ffi;
import 'dart:io';

import 'flutter_opengl_ffi.dart';
import 'opengl_backend.dart';
import 'opengl_backend_native.dart';

class OpenGLController {
  static OpenGLController? _instance;

  factory OpenGLController() => _instance ??= OpenGLController._();

  OpenGLController._();

  late ffi.DynamicLibrary nativeLib;
  late final OpenGLBackend openglFFI;

  void initializeGL() {
    nativeLib = Platform.isAndroid
        ? ffi.DynamicLibrary.open("libflutter_opengl_plugin.so")
        : Platform.isWindows
            ? ffi.DynamicLibrary.open("flutter_opengl_plugin.dll")
            : ffi.DynamicLibrary.process(); // Linux, macOS & iOS
    final ffiObj = FlutterOpenGLFfi.fromLookup(nativeLib.lookup);
    openglFFI = NativeOpenGLBackend(ffiObj);
  }
}
