import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'flutter_opengl_ffi.dart';
import 'opengl_backend.dart';
import 'opengl_enums.dart';

/// Native FFI implementation of [OpenGLBackend].
class NativeOpenGLBackend implements OpenGLBackend {
  final FlutterOpenGLFfi _ffi;

  NativeOpenGLBackend(this._ffi);

  @override
  bool rendererStatus() => _ffi.rendererStatus();

  @override
  Size getTextureSize() => _ffi.getTextureSize();

  @override
  void startThread() => _ffi.startThread();

  @override
  void stopThread() => _ffi.stopThread();

  @override
  String setShader(bool isContinuous, String vertexShader,
          String fragmentShader) =>
      _ffi.setShader(isContinuous, vertexShader, fragmentShader);

  @override
  String setShaderToy(String fragmentShader) =>
      _ffi.setShaderToy(fragmentShader);

  @override
  String getVertexShader() => _ffi.getVertexShader();

  @override
  String getFragmentShader() => _ffi.getFragmentShader();

  @override
  void addShaderToyUniforms() => _ffi.addShaderToyUniforms();

  @override
  void setMousePosition(Offset startingPos, Offset pos,
          PointerEventType eventType, Size twSize) =>
      _ffi.setMousePosition(startingPos, pos, eventType, twSize);

  @override
  double getFps() => _ffi.getFps();

  @override
  void setClearColor(int clearR, int clearG, int clearB, int clearA) =>
      _ffi.setClearColor(clearR, clearG, clearB, clearA);

  @override
  bool addBoolUniform(String name, bool val) =>
      _ffi.addBoolUniform(name, val);

  @override
  bool addIntUniform(String name, int val) => _ffi.addIntUniform(name, val);

  @override
  bool addFloatUniform(String name, double val) =>
      _ffi.addFloatUniform(name, val);

  @override
  bool addVec2Uniform(String name, List<double> val) =>
      _ffi.addVec2Uniform(name, val);

  @override
  bool addVec3Uniform(String name, List<double> val) =>
      _ffi.addVec3Uniform(name, val);

  @override
  bool addVec4Uniform(String name, List<double> val) =>
      _ffi.addVec4Uniform(name, val);

  @override
  bool addMat2Uniform(String name, List<double> val) =>
      _ffi.addMat2Uniform(name, val);

  @override
  bool addMat3Uniform(String name, List<double> val) =>
      _ffi.addMat3Uniform(name, val);

  @override
  bool addMat4Uniform(String name, List<double> val) =>
      _ffi.addMat4Uniform(name, val);

  @override
  bool setBoolUniform(String name, bool val) =>
      _ffi.setBoolUniform(name, val);

  @override
  bool setIntUniform(String name, int val) => _ffi.setIntUniform(name, val);

  @override
  bool setFloatUniform(String name, double val) =>
      _ffi.setFloatUniform(name, val);

  @override
  bool setVec2Uniform(String name, List<double> val) =>
      _ffi.setVec2Uniform(name, val);

  @override
  bool setVec3Uniform(String name, List<double> val) =>
      _ffi.setVec3Uniform(name, val);

  @override
  bool setVec4Uniform(String name, List<double> val) =>
      _ffi.setVec4Uniform(name, val);

  @override
  bool setMat2Uniform(String name, List<double> val) =>
      _ffi.setMat2Uniform(name, val);

  @override
  bool setMat3Uniform(String name, List<double> val) =>
      _ffi.setMat3Uniform(name, val);

  @override
  bool setMat4Uniform(String name, List<double> val) =>
      _ffi.setMat4Uniform(name, val);

  @override
  bool removeUniform(String name) => _ffi.removeUniform(name);

  @override
  bool addSampler2DUniform(
          String name, int width, int height, Uint8List val) =>
      _ffi.addSampler2DUniform(name, width, height, val);

  @override
  bool replaceSampler2DUniform(
          String name, int width, int height, Uint8List val) =>
      _ffi.replaceSampler2DUniform(name, width, height, val);

  @override
  bool setSampler2DUniform(String name, Uint8List val) =>
      _ffi.setSampler2DUniform(name, val);

  @override
  bool startCaptureOnSampler2D(String name, String completeFilePath) =>
      _ffi.startCaptureOnSampler2D(name, completeFilePath);

  @override
  bool stopCapture() => _ffi.stopCapture();
}
