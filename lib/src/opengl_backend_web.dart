import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'opengl_backend.dart';
import 'opengl_enums.dart';

typedef _GL = web.WebGL2RenderingContext;

class _UniformInfo {
  final UniformType type;
  web.WebGLUniformLocation? location;
  dynamic value;
  _UniformInfo(this.type, this.value, [this.location]);
}

class _TextureInfo {
  web.WebGLTexture? texture;
  int width;
  int height;
  int textureUnit;
  web.WebGLUniformLocation? location;
  _TextureInfo(this.texture, this.width, this.height, this.textureUnit);
}

/// WebGL2 implementation of [OpenGLBackend].
class WebGLBackend implements OpenGLBackend {
  web.HTMLCanvasElement? _canvas;
  _GL? _gl;
  web.WebGLProgram? _program;
  web.WebGLBuffer? _vbo;

  int _width = 0;
  int _height = 0;
  bool _running = false;
  bool _ready = false;
  int _animFrameId = 0;

  String _vertexShaderSrc = '';
  String _fragmentShaderSrc = '';

  double _startTime = 0;
  double _mouseX = 0;
  double _mouseY = 0;
  double _mouseZ = 0;
  double _mouseW = 0;
  int _frame = 0;

  double _fps = 0;
  double _lastFpsTime = 0;
  int _fpsFrameCount = 0;

  double _clearR = 0, _clearG = 0, _clearB = 0, _clearA = 1;

  final Map<String, _UniformInfo> _uniforms = {};
  final Map<String, _TextureInfo> _textures = {};
  int _nextTextureUnit = 0;
  bool _isShaderToy = false;

  String get viewType => 'flutter_opengl_webgl_$hashCode';

  web.HTMLCanvasElement createCanvas(int width, int height) {
    _width = width;
    _height = height;

    _canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height
      ..style.width = '100%'
      ..style.height = '100%';

    _gl = _canvas!.getContext('webgl2') as _GL?;
    if (_gl == null) {
      throw UnsupportedError('WebGL2 is not supported in this browser.');
    }

    _gl!.viewport(0, 0, width, height);
    _ready = true;
    return _canvas!;
  }

  @override
  bool rendererStatus() => _ready;

  @override
  Size getTextureSize() {
    if (!_ready) return const Size(-1, -1);
    return Size(_width.toDouble(), _height.toDouble());
  }

  @override
  void startThread() {
    if (_running || !_ready) return;
    _running = true;
    _startTime = _now();
    _lastFpsTime = _startTime;
    _fpsFrameCount = 0;
    _frame = 0;
    _animFrameId = web.window.requestAnimationFrame(_renderLoop.toJS);
  }

  @override
  void stopThread() {
    _running = false;
    if (_animFrameId != 0) {
      web.window.cancelAnimationFrame(_animFrameId);
      _animFrameId = 0;
    }
    _deleteProgram();
  }

  @override
  String setShader(
      bool isContinuous, String vertexShader, String fragmentShader) {
    _isShaderToy = false;
    _vertexShaderSrc = vertexShader;
    _fragmentShaderSrc = fragmentShader;
    return _compileAndLink(vertexShader, fragmentShader);
  }

  @override
  String setShaderToy(String fragmentShader) {
    _isShaderToy = true;

    _vertexShaderSrc = '''#version 300 es
precision highp float;
in vec4 a_Position;
void main() {
  gl_Position = a_Position;
}
''';

    _fragmentShaderSrc = '''#version 300 es
precision highp float;
out vec4 fragColor;
uniform float iTime;
uniform int iFrame;
uniform vec4 iMouse;
uniform vec3 iResolution;
uniform sampler2D iChannel0;
uniform sampler2D iChannel1;
uniform sampler2D iChannel2;
uniform sampler2D iChannel3;

$fragmentShader

void main() {
  mainImage(fragColor, gl_FragCoord.xy);
}
''';

    final err = _compileAndLink(_vertexShaderSrc, _fragmentShaderSrc);
    if (err.isEmpty) {
      addShaderToyUniforms();
    }
    return err;
  }

  @override
  String getVertexShader() => _vertexShaderSrc;

  @override
  String getFragmentShader() => _fragmentShaderSrc;

  @override
  void addShaderToyUniforms() {
    for (int i = 0; i < 4; i++) {
      final name = 'iChannel$i';
      if (!_textures.containsKey(name)) {
        _addTextureUniform(name, 1, 1, Uint8List.fromList([0, 0, 0, 255]));
      }
    }
  }

  @override
  void setMousePosition(Offset startingPos, Offset pos,
      PointerEventType eventType, Size twSize) {
    if (twSize == Size.zero) return;

    final scaleX = _width / twSize.width;
    final scaleY = _height / twSize.height;

    _mouseX = pos.dx * scaleX;
    _mouseY = (_height - pos.dy * scaleY);

    if (eventType == PointerEventType.onPointerDown ||
        eventType == PointerEventType.onPointerMove) {
      _mouseZ = startingPos.dx * scaleX;
      _mouseW = -startingPos.dy * scaleY;
    } else {
      _mouseZ = -startingPos.dx * scaleX;
      _mouseW = -startingPos.dy * scaleY;
    }
  }

  @override
  double getFps() => _fps;

  @override
  void setClearColor(int clearR, int clearG, int clearB, int clearA) {
    _clearR = clearR / 255.0;
    _clearG = clearG / 255.0;
    _clearB = clearB / 255.0;
    _clearA = clearA / 255.0;
  }

  @override
  bool addBoolUniform(String name, bool val) =>
      _addUniform(name, UniformType.uniformBool, val);

  @override
  bool addIntUniform(String name, int val) =>
      _addUniform(name, UniformType.uniformInt, val);

  @override
  bool addFloatUniform(String name, double val) =>
      _addUniform(name, UniformType.uniformFloat, val);

  @override
  bool addVec2Uniform(String name, List<double> val) =>
      _addUniform(name, UniformType.uniformVec2, Float32List.fromList(val));

  @override
  bool addVec3Uniform(String name, List<double> val) =>
      _addUniform(name, UniformType.uniformVec3, Float32List.fromList(val));

  @override
  bool addVec4Uniform(String name, List<double> val) =>
      _addUniform(name, UniformType.uniformVec4, Float32List.fromList(val));

  @override
  bool addMat2Uniform(String name, List<double> val) =>
      _addUniform(name, UniformType.uniformMat2, Float32List.fromList(val));

  @override
  bool addMat3Uniform(String name, List<double> val) =>
      _addUniform(name, UniformType.uniformMat3, Float32List.fromList(val));

  @override
  bool addMat4Uniform(String name, List<double> val) =>
      _addUniform(name, UniformType.uniformMat4, Float32List.fromList(val));

  @override
  bool setBoolUniform(String name, bool val) => _setUniformValue(name, val);

  @override
  bool setIntUniform(String name, int val) => _setUniformValue(name, val);

  @override
  bool setFloatUniform(String name, double val) => _setUniformValue(name, val);

  @override
  bool setVec2Uniform(String name, List<double> val) =>
      _setUniformValue(name, Float32List.fromList(val));

  @override
  bool setVec3Uniform(String name, List<double> val) =>
      _setUniformValue(name, Float32List.fromList(val));

  @override
  bool setVec4Uniform(String name, List<double> val) =>
      _setUniformValue(name, Float32List.fromList(val));

  @override
  bool setMat2Uniform(String name, List<double> val) =>
      _setUniformValue(name, Float32List.fromList(val));

  @override
  bool setMat3Uniform(String name, List<double> val) =>
      _setUniformValue(name, Float32List.fromList(val));

  @override
  bool setMat4Uniform(String name, List<double> val) =>
      _setUniformValue(name, Float32List.fromList(val));

  @override
  bool removeUniform(String name) {
    _uniforms.remove(name);
    final tex = _textures.remove(name);
    if (tex != null && _gl != null) {
      _gl!.deleteTexture(tex.texture);
    }
    return true;
  }

  @override
  bool addSampler2DUniform(
          String name, int width, int height, Uint8List val) =>
      _addTextureUniform(name, width, height, val);

  @override
  bool replaceSampler2DUniform(
      String name, int width, int height, Uint8List val) {
    final old = _textures[name];
    if (old != null && _gl != null) {
      _gl!.deleteTexture(old.texture);
    }
    return _addTextureUniform(name, width, height, val, old?.textureUnit);
  }

  @override
  bool setSampler2DUniform(String name, Uint8List val) {
    final info = _textures[name];
    if (info == null || _gl == null) return false;

    final gl = _gl!;
    gl.activeTexture(_GL.TEXTURE0 + info.textureUnit);
    gl.bindTexture(_GL.TEXTURE_2D, info.texture);
    gl.texSubImage2D(
      _GL.TEXTURE_2D,
      0,
      0,
      0,
      info.width.toJS,
      info.height.toJS,
      _GL.RGBA.toJS,
      _GL.UNSIGNED_BYTE,
      val.toJS,
    );
    return true;
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
    final canvas = createCanvas(width, height);

    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId, {Object? params}) => canvas,
    );

    return 0; // dummy texture ID; web uses HtmlElementView
  }

  // ---- Private ----

  double _now() => web.window.performance.now() / 1000.0;

  void _renderLoop(JSNumber timestamp) {
    if (!_running) return;

    // Always schedule next frame while running
    _animFrameId = web.window.requestAnimationFrame(_renderLoop.toJS);

    final gl = _gl;
    if (gl == null || _program == null) return;

    final now = _now();

    _fpsFrameCount++;
    final elapsed = now - _lastFpsTime;
    if (elapsed >= 1.0) {
      _fps = _fpsFrameCount / elapsed;
      _fpsFrameCount = 0;
      _lastFpsTime = now;
    }

    gl.clearColor(_clearR, _clearG, _clearB, _clearA);
    gl.clear(_GL.COLOR_BUFFER_BIT);

    gl.useProgram(_program);

    if (_isShaderToy) {
      final iTime = now - _startTime;
      _setGLUniform('iTime', UniformType.uniformFloat, iTime);
      _setGLUniform('iFrame', UniformType.uniformInt, _frame);
      _setGLUniform('iResolution', UniformType.uniformVec3,
          Float32List.fromList([_width.toDouble(), _height.toDouble(), 1.0]));
      _setGLUniform('iMouse', UniformType.uniformVec4,
          Float32List.fromList([_mouseX, _mouseY, _mouseZ, _mouseW]));
    }

    for (final entry in _uniforms.entries) {
      final info = entry.value;
      info.location ??= gl.getUniformLocation(_program!, entry.key);
      _applyUniform(info);
    }

    for (final entry in _textures.entries) {
      final info = entry.value;
      info.location ??= gl.getUniformLocation(_program!, entry.key);
      if (info.location != null) {
        gl.activeTexture(_GL.TEXTURE0 + info.textureUnit);
        gl.bindTexture(_GL.TEXTURE_2D, info.texture);
        gl.uniform1i(info.location, info.textureUnit);
      }
    }

    gl.bindBuffer(_GL.ARRAY_BUFFER, _vbo);
    final posLoc = gl.getAttribLocation(_program!, 'a_Position');
    if (posLoc >= 0) {
      gl.enableVertexAttribArray(posLoc);
      gl.vertexAttribPointer(posLoc, 2, _GL.FLOAT, false, 0, 0);
    }
    gl.drawArrays(_GL.TRIANGLES, 0, 6);

    _frame++;
  }

  String _compileAndLink(String vertexSrc, String fragmentSrc) {
    final gl = _gl;
    if (gl == null) return 'WebGL2 context not initialized';

    _deleteProgram();

    final vs = gl.createShader(_GL.VERTEX_SHADER)!;
    gl.shaderSource(vs, vertexSrc);
    gl.compileShader(vs);
    if (!(gl.getShaderParameter(vs, _GL.COMPILE_STATUS) as JSBoolean)
        .toDart) {
      final log = gl.getShaderInfoLog(vs) ?? 'Unknown vertex shader error';
      gl.deleteShader(vs);
      return 'VERTEX: $log';
    }

    final fs = gl.createShader(_GL.FRAGMENT_SHADER)!;
    gl.shaderSource(fs, fragmentSrc);
    gl.compileShader(fs);
    if (!(gl.getShaderParameter(fs, _GL.COMPILE_STATUS) as JSBoolean)
        .toDart) {
      final log = gl.getShaderInfoLog(fs) ?? 'Unknown fragment shader error';
      gl.deleteShader(vs);
      gl.deleteShader(fs);
      return 'FRAGMENT: $log';
    }

    final prog = gl.createProgram()!;
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!(gl.getProgramParameter(prog, _GL.LINK_STATUS) as JSBoolean)
        .toDart) {
      final log = gl.getProgramInfoLog(prog) ?? 'Unknown link error';
      gl.deleteProgram(prog);
      gl.deleteShader(vs);
      gl.deleteShader(fs);
      return 'LINK: $log';
    }

    gl.deleteShader(vs);
    gl.deleteShader(fs);
    _program = prog;

    for (final info in _uniforms.values) {
      info.location = null;
    }
    for (final info in _textures.values) {
      info.location = null;
    }

    _setupQuad();
    return '';
  }

  void _setupQuad() {
    final gl = _gl!;
    final vertices = Float32List.fromList([
      -1, -1, 1, -1, -1, 1,
      -1, 1, 1, -1, 1, 1,
    ]);

    _vbo = gl.createBuffer();
    gl.bindBuffer(_GL.ARRAY_BUFFER, _vbo);
    gl.bufferData(_GL.ARRAY_BUFFER, vertices.toJS, _GL.STATIC_DRAW);
  }

  void _deleteProgram() {
    if (_program != null && _gl != null) {
      _gl!.deleteProgram(_program);
      _program = null;
    }
    if (_vbo != null && _gl != null) {
      _gl!.deleteBuffer(_vbo);
      _vbo = null;
    }
  }

  bool _addUniform(String name, UniformType type, dynamic value) {
    if (_program == null || _gl == null) return false;
    final loc = _gl!.getUniformLocation(_program!, name);
    _uniforms[name] = _UniformInfo(type, value, loc);
    return true;
  }

  bool _setUniformValue(String name, dynamic value) {
    final info = _uniforms[name];
    if (info == null) return false;
    info.value = value;
    return true;
  }

  void _setGLUniform(String name, UniformType type, dynamic value) {
    if (_gl == null || _program == null) return;
    final loc = _gl!.getUniformLocation(_program!, name);
    if (loc == null) return;
    _applyUniform(_UniformInfo(type, value, loc));
  }

  void _applyUniform(_UniformInfo info) {
    final gl = _gl!;
    final loc = info.location;
    if (loc == null) return;

    switch (info.type) {
      case UniformType.uniformBool:
        gl.uniform1i(loc, (info.value as bool) ? 1 : 0);
      case UniformType.uniformInt:
        gl.uniform1i(loc, info.value as int);
      case UniformType.uniformFloat:
        gl.uniform1f(loc, (info.value as num).toDouble());
      case UniformType.uniformVec2:
        gl.uniform2fv(loc, (info.value as Float32List).toJS);
      case UniformType.uniformVec3:
        gl.uniform3fv(loc, (info.value as Float32List).toJS);
      case UniformType.uniformVec4:
        gl.uniform4fv(loc, (info.value as Float32List).toJS);
      case UniformType.uniformMat2:
        gl.uniformMatrix2fv(loc, false, (info.value as Float32List).toJS);
      case UniformType.uniformMat3:
        gl.uniformMatrix3fv(loc, false, (info.value as Float32List).toJS);
      case UniformType.uniformMat4:
        gl.uniformMatrix4fv(loc, false, (info.value as Float32List).toJS);
      case UniformType.uniformSampler2D:
        break;
    }
  }

  bool _addTextureUniform(String name, int width, int height, Uint8List val,
      [int? reuseUnit]) {
    final gl = _gl;
    if (gl == null) return false;

    final unit = reuseUnit ?? _nextTextureUnit++;
    final tex = gl.createTexture()!;

    gl.activeTexture(_GL.TEXTURE0 + unit);
    gl.bindTexture(_GL.TEXTURE_2D, tex);
    gl.texParameteri(_GL.TEXTURE_2D, _GL.TEXTURE_MIN_FILTER, _GL.LINEAR);
    gl.texParameteri(_GL.TEXTURE_2D, _GL.TEXTURE_MAG_FILTER, _GL.LINEAR);
    gl.texParameteri(_GL.TEXTURE_2D, _GL.TEXTURE_WRAP_S, _GL.CLAMP_TO_EDGE);
    gl.texParameteri(_GL.TEXTURE_2D, _GL.TEXTURE_WRAP_T, _GL.CLAMP_TO_EDGE);
    gl.texImage2D(
      _GL.TEXTURE_2D,
      0,
      _GL.RGBA,
      width.toJS,
      height.toJS,
      0.toJS,
      _GL.RGBA,
      _GL.UNSIGNED_BYTE,
      val.toJS,
    );

    _textures[name] = _TextureInfo(tex, width, height, unit);
    return true;
  }
}
