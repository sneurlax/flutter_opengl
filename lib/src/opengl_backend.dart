import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'opengl_enums.dart';

/// Platform-independent interface for OpenGL rendering operations.
///
/// Implemented by [NativeOpenGLBackend] (FFI) and [WebGLBackend] (WebGL2).
abstract class OpenGLBackend {
  bool rendererStatus();

  Size getTextureSize();

  void startThread();

  void stopThread();

  String setShader(
    bool isContinuous,
    String vertexShader,
    String fragmentShader,
  );

  String setShaderToy(String fragmentShader);

  String getVertexShader();

  String getFragmentShader();

  void addShaderToyUniforms();

  void setMousePosition(
    Offset startingPos,
    Offset pos,
    PointerEventType eventType,
    Size twSize,
  );

  double getFps();

  void setClearColor(int clearR, int clearG, int clearB, int clearA);

  bool addBoolUniform(String name, bool val);
  bool addIntUniform(String name, int val);
  bool addFloatUniform(String name, double val);
  bool addVec2Uniform(String name, List<double> val);
  bool addVec3Uniform(String name, List<double> val);
  bool addVec4Uniform(String name, List<double> val);
  bool addMat2Uniform(String name, List<double> val);
  bool addMat3Uniform(String name, List<double> val);
  bool addMat4Uniform(String name, List<double> val);

  bool setBoolUniform(String name, bool val);
  bool setIntUniform(String name, int val);
  bool setFloatUniform(String name, double val);
  bool setVec2Uniform(String name, List<double> val);
  bool setVec3Uniform(String name, List<double> val);
  bool setVec4Uniform(String name, List<double> val);
  bool setMat2Uniform(String name, List<double> val);
  bool setMat3Uniform(String name, List<double> val);
  bool setMat4Uniform(String name, List<double> val);

  bool removeUniform(String name);

  bool addSampler2DUniform(String name, int width, int height, Uint8List val);
  bool replaceSampler2DUniform(
      String name, int width, int height, Uint8List val);
  bool setSampler2DUniform(String name, Uint8List val);

  bool startCaptureOnSampler2D(String name, String completeFilePath);
  bool stopCapture();

  /// Allocate a rendering surface of the given [width] x [height] and return
  /// a texture ID that can be passed to [OpenGLTexture].
  ///
  /// On native platforms this calls into the platform host via a method
  /// channel; on web it creates an HTML canvas and registers a platform view.
  Future<int> createSurface(int width, int height);
}
