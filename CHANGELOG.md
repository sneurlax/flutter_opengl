## 0.10.0

- Add Web platform support via a WebGL2 rendering backend
- Add iOS platform support using OpenGL ES 3.0
- Add macOS platform support using CGL and FlutterTexture
- Bundle GLEW 2.2.0 and GLM headers for Windows (no manual setup required)
- Make OpenCV optional on Android and Windows
- Modernize Android plugin configuration for AGP 8.x
- Refactor Dart layer with abstract OpenGLBackend interface and conditional imports
- Update SDK constraints and dependencies for Dart 3.x

## 0.9.0

- Code rewritten with FFI-based rendering pipeline
- Support for Android, Linux, and Windows
