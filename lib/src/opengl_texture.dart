export 'opengl_texture_stub.dart'
    if (dart.library.ffi) 'opengl_texture_native.dart'
    if (dart.library.js_interop) 'opengl_texture_web.dart';
