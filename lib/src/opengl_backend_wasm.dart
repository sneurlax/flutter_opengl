import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'opengl_backend.dart';
import 'opengl_enums.dart';

// ---------------------------------------------------------------------------
// JS interop bindings for the wasm-bindgen generated WasmRenderer class.
// The JS glue is loaded from web/pkg/flutter_opengl_rust.js.
// ---------------------------------------------------------------------------

@JS('__flutter_opengl_wasm_init')
external JSPromise<JSAny?> _wasmInit();

@JS('__flutter_opengl_WasmRenderer')
extension type _WasmRenderer._(JSObject _) implements JSObject {
  external factory _WasmRenderer(web.HTMLCanvasElement canvas, JSNumber width, JSNumber height);
  external void free();

  // Lifecycle
  external void start();
  external void stop();
  external JSBoolean renderer_status();

  // Rendering
  external void render_frame();

  // Shader
  external JSString set_shader(
      JSBoolean isContinuous, JSString vertexSrc, JSString fragmentSrc);
  external JSString set_shader_toy(JSString fragmentSrc);
  external JSString get_vertex_shader();
  external JSString get_fragment_shader();

  // ShaderToy helpers
  external void add_shader_toy_uniforms();
  external void set_mouse_position(
      JSNumber x, JSNumber y, JSNumber z, JSNumber w);

  // Uniform add
  external JSBoolean add_bool_uniform(JSString name, JSBoolean val);
  external JSBoolean add_int_uniform(JSString name, JSNumber val);
  external JSBoolean add_float_uniform(JSString name, JSNumber val);
  external JSBoolean add_vec2_uniform(JSString name, JSNumber x, JSNumber y);
  external JSBoolean add_vec3_uniform(
      JSString name, JSNumber x, JSNumber y, JSNumber z);
  external JSBoolean add_vec4_uniform(
      JSString name, JSNumber x, JSNumber y, JSNumber z, JSNumber w);
  external JSBoolean add_mat2_uniform(
      JSString name, JSNumber v0, JSNumber v1, JSNumber v2, JSNumber v3);
  external JSBoolean add_mat3_uniform(
      JSString name,
      JSNumber v0, JSNumber v1, JSNumber v2,
      JSNumber v3, JSNumber v4, JSNumber v5,
      JSNumber v6, JSNumber v7, JSNumber v8);
  external JSBoolean add_mat4_uniform(
      JSString name,
      JSNumber v0, JSNumber v1, JSNumber v2, JSNumber v3,
      JSNumber v4, JSNumber v5, JSNumber v6, JSNumber v7,
      JSNumber v8, JSNumber v9, JSNumber v10, JSNumber v11,
      JSNumber v12, JSNumber v13, JSNumber v14, JSNumber v15);

  // Uniform set
  external JSBoolean set_bool_uniform(JSString name, JSBoolean val);
  external JSBoolean set_int_uniform(JSString name, JSNumber val);
  external JSBoolean set_float_uniform(JSString name, JSNumber val);
  external JSBoolean set_vec2_uniform(JSString name, JSNumber x, JSNumber y);
  external JSBoolean set_vec3_uniform(
      JSString name, JSNumber x, JSNumber y, JSNumber z);
  external JSBoolean set_vec4_uniform(
      JSString name, JSNumber x, JSNumber y, JSNumber z, JSNumber w);
  external JSBoolean set_mat2_uniform(
      JSString name, JSNumber v0, JSNumber v1, JSNumber v2, JSNumber v3);
  external JSBoolean set_mat3_uniform(
      JSString name,
      JSNumber v0, JSNumber v1, JSNumber v2,
      JSNumber v3, JSNumber v4, JSNumber v5,
      JSNumber v6, JSNumber v7, JSNumber v8);
  external JSBoolean set_mat4_uniform(
      JSString name,
      JSNumber v0, JSNumber v1, JSNumber v2, JSNumber v3,
      JSNumber v4, JSNumber v5, JSNumber v6, JSNumber v7,
      JSNumber v8, JSNumber v9, JSNumber v10, JSNumber v11,
      JSNumber v12, JSNumber v13, JSNumber v14, JSNumber v15);

  // Uniform removal
  external JSBoolean remove_uniform(JSString name);

  // Sampler2D
  external JSBoolean add_sampler2d_uniform(
      JSString name, JSNumber width, JSNumber height, JSUint8Array data);
  external JSBoolean replace_sampler2d_uniform(
      JSString name, JSNumber width, JSNumber height, JSUint8Array data);

  // Getters
  external JSNumber get_fps();
  external JSNumber get_texture_width();
  external JSNumber get_texture_height();
}

/// WebGL2 backend powered by the Rust WASM module (via wasm-bindgen).
///
/// Replaces the pure-Dart [WebGLBackend] with the shared Rust rendering engine.
class WasmBackend implements OpenGLBackend {
  static bool _wasmLoaded = false;

  _WasmRenderer? _renderer;
  int _width = 0;
  int _height = 0;
  bool _running = false;
  int _animFrameId = 0;

  String get viewType => 'flutter_opengl_wasm_$hashCode';

  static Future<void> ensureWasmLoaded() async {
    if (_wasmLoaded) return;
    await _wasmInit().toDart;
    _wasmLoaded = true;
  }

  @override
  bool rendererStatus() => _renderer != null;

  @override
  Size getTextureSize() {
    if (_renderer == null) return const Size(-1, -1);
    return Size(_width.toDouble(), _height.toDouble());
  }

  @override
  void stopThread() {
    _running = false;
    _renderer?.stop();
    if (_animFrameId != 0) {
      web.window.cancelAnimationFrame(_animFrameId);
      _animFrameId = 0;
    }
  }

  void _renderLoop(JSNumber timestamp) {
    if (!_running) return;
    _animFrameId = web.window.requestAnimationFrame(_renderLoop.toJS);
    _renderer?.render_frame();
  }

  @override
  String setShader(
      bool isContinuous, String vertexShader, String fragmentShader) {
    if (_renderer == null) return 'Renderer not initialized';
    return _renderer!
        .set_shader(isContinuous.toJS, vertexShader.toJS, fragmentShader.toJS)
        .toDart;
  }

  @override
  String setShaderToy(String fragmentShader) {
    if (_renderer == null) return 'Renderer not initialized';
    return _renderer!.set_shader_toy(fragmentShader.toJS).toDart;
  }

  @override
  String getVertexShader() =>
      _renderer?.get_vertex_shader().toDart ?? '';

  @override
  String getFragmentShader() =>
      _renderer?.get_fragment_shader().toDart ?? '';

  @override
  void addShaderToyUniforms() {
    _renderer?.add_shader_toy_uniforms();
  }

  @override
  void setMousePosition(
      Offset startingPos, Offset pos, PointerEventType eventType, Size twSize) {
    if (_renderer == null || twSize == Size.zero) return;

    final scaleX = _width / twSize.width;
    final scaleY = _height / twSize.height;

    final mx = pos.dx * scaleX;
    final my = _height - pos.dy * scaleY;

    double mz, mw;
    if (eventType == PointerEventType.onPointerDown ||
        eventType == PointerEventType.onPointerMove) {
      mz = startingPos.dx * scaleX;
      mw = -startingPos.dy * scaleY;
    } else {
      mz = -startingPos.dx * scaleX;
      mw = -startingPos.dy * scaleY;
    }

    _renderer!.set_mouse_position(
        mx.toJS, my.toJS, mz.toJS, mw.toJS);
  }

  @override
  double getFps() => _renderer?.get_fps().toDartDouble ?? 0;

  @override
  void setClearColor(int clearR, int clearG, int clearB, int clearA) {
    // The Rust WasmRenderer doesn't expose setClearColor — it uses black.
    // This is a no-op for now; could be added to wasm.rs if needed.
  }

  // ---------------------------------------------------------------------------
  // Uniform add
  // ---------------------------------------------------------------------------

  @override
  bool addBoolUniform(String name, bool val) =>
      _renderer?.add_bool_uniform(name.toJS, val.toJS).toDart ?? false;

  @override
  bool addIntUniform(String name, int val) =>
      _renderer?.add_int_uniform(name.toJS, val.toJS).toDart ?? false;

  @override
  bool addFloatUniform(String name, double val) =>
      _renderer?.add_float_uniform(name.toJS, val.toJS).toDart ?? false;

  @override
  bool addVec2Uniform(String name, List<double> val) =>
      _renderer?.add_vec2_uniform(name.toJS, val[0].toJS, val[1].toJS).toDart ??
      false;

  @override
  bool addVec3Uniform(String name, List<double> val) =>
      _renderer?.add_vec3_uniform(
              name.toJS, val[0].toJS, val[1].toJS, val[2].toJS)
          .toDart ??
      false;

  @override
  bool addVec4Uniform(String name, List<double> val) =>
      _renderer?.add_vec4_uniform(
              name.toJS, val[0].toJS, val[1].toJS, val[2].toJS, val[3].toJS)
          .toDart ??
      false;

  @override
  bool addMat2Uniform(String name, List<double> val) =>
      _renderer?.add_mat2_uniform(
              name.toJS, val[0].toJS, val[1].toJS, val[2].toJS, val[3].toJS)
          .toDart ??
      false;

  @override
  bool addMat3Uniform(String name, List<double> val) =>
      _renderer?.add_mat3_uniform(
              name.toJS,
              val[0].toJS, val[1].toJS, val[2].toJS,
              val[3].toJS, val[4].toJS, val[5].toJS,
              val[6].toJS, val[7].toJS, val[8].toJS)
          .toDart ??
      false;

  @override
  bool addMat4Uniform(String name, List<double> val) =>
      _renderer?.add_mat4_uniform(
              name.toJS,
              val[0].toJS, val[1].toJS, val[2].toJS, val[3].toJS,
              val[4].toJS, val[5].toJS, val[6].toJS, val[7].toJS,
              val[8].toJS, val[9].toJS, val[10].toJS, val[11].toJS,
              val[12].toJS, val[13].toJS, val[14].toJS, val[15].toJS)
          .toDart ??
      false;

  // ---------------------------------------------------------------------------
  // Uniform set
  // ---------------------------------------------------------------------------

  @override
  bool setBoolUniform(String name, bool val) =>
      _renderer?.set_bool_uniform(name.toJS, val.toJS).toDart ?? false;

  @override
  bool setIntUniform(String name, int val) =>
      _renderer?.set_int_uniform(name.toJS, val.toJS).toDart ?? false;

  @override
  bool setFloatUniform(String name, double val) =>
      _renderer?.set_float_uniform(name.toJS, val.toJS).toDart ?? false;

  @override
  bool setVec2Uniform(String name, List<double> val) =>
      _renderer?.set_vec2_uniform(name.toJS, val[0].toJS, val[1].toJS).toDart ??
      false;

  @override
  bool setVec3Uniform(String name, List<double> val) =>
      _renderer?.set_vec3_uniform(
              name.toJS, val[0].toJS, val[1].toJS, val[2].toJS)
          .toDart ??
      false;

  @override
  bool setVec4Uniform(String name, List<double> val) =>
      _renderer?.set_vec4_uniform(
              name.toJS, val[0].toJS, val[1].toJS, val[2].toJS, val[3].toJS)
          .toDart ??
      false;

  @override
  bool setMat2Uniform(String name, List<double> val) =>
      _renderer?.set_mat2_uniform(
              name.toJS, val[0].toJS, val[1].toJS, val[2].toJS, val[3].toJS)
          .toDart ??
      false;

  @override
  bool setMat3Uniform(String name, List<double> val) =>
      _renderer?.set_mat3_uniform(
              name.toJS,
              val[0].toJS, val[1].toJS, val[2].toJS,
              val[3].toJS, val[4].toJS, val[5].toJS,
              val[6].toJS, val[7].toJS, val[8].toJS)
          .toDart ??
      false;

  @override
  bool setMat4Uniform(String name, List<double> val) =>
      _renderer?.set_mat4_uniform(
              name.toJS,
              val[0].toJS, val[1].toJS, val[2].toJS, val[3].toJS,
              val[4].toJS, val[5].toJS, val[6].toJS, val[7].toJS,
              val[8].toJS, val[9].toJS, val[10].toJS, val[11].toJS,
              val[12].toJS, val[13].toJS, val[14].toJS, val[15].toJS)
          .toDart ??
      false;

  // ---------------------------------------------------------------------------
  // Uniform removal
  // ---------------------------------------------------------------------------

  @override
  bool removeUniform(String name) =>
      _renderer?.remove_uniform(name.toJS).toDart ?? false;

  // ---------------------------------------------------------------------------
  // Sampler2D
  // ---------------------------------------------------------------------------

  @override
  bool addSampler2DUniform(
          String name, int width, int height, Uint8List val) =>
      _renderer?.add_sampler2d_uniform(
              name.toJS, width.toJS, height.toJS, val.toJS)
          .toDart ??
      false;

  @override
  bool replaceSampler2DUniform(
          String name, int width, int height, Uint8List val) =>
      _renderer?.replace_sampler2d_uniform(
              name.toJS, width.toJS, height.toJS, val.toJS)
          .toDart ??
      false;

  @override
  bool setSampler2DUniform(String name, Uint8List val) {
    // The Rust WasmRenderer doesn't have a separate setSampler2D — use replace
    // with current dimensions.
    if (_renderer == null) return false;
    final w = _renderer!.get_texture_width().toDartInt;
    final h = _renderer!.get_texture_height().toDartInt;
    return _renderer!
        .replace_sampler2d_uniform(name.toJS, w.toJS, h.toJS, val.toJS)
        .toDart;
  }

  @override
  bool startCaptureOnSampler2D(String name, String completeFilePath) {
    throw UnsupportedError(
        'startCaptureOnSampler2D is not supported on web.');
  }

  @override
  bool stopCapture() {
    throw UnsupportedError('stopCapture is not supported on web.');
  }

  @override
  Future<int> createSurface(int width, int height) async {
    await ensureWasmLoaded();

    _width = width;
    _height = height;

    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height
      ..style.width = '100%'
      ..style.height = '100%';

    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId, {Object? params}) => canvas,
    );

    // Create the WasmRenderer immediately — the constructor now accepts
    // the canvas element directly, so it doesn't need to be in the DOM.
    _renderer = _WasmRenderer(canvas, _width.toJS, _height.toJS);

    return 0;
  }

  @override
  void startThread() {
    if (_running || _renderer == null) return;
    _running = true;
    _renderer!.start();
    _animFrameId = web.window.requestAnimationFrame(_renderLoop.toJS);
  }
}
