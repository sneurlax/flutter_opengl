import 'package:flutter/scheduler.dart';
import 'package:flutter_opengl/flutter_opengl.dart';

enum GameState { menu, playing, dead }

class Rock {
  double x;
  double gapY;
  double gapH;
  bool scored;

  Rock({required this.x, required this.gapY, required this.gapH})
      : scored = false;
}

class SkyFairyGame {
  // Physics
  static const double gravity = 1.8;
  static const double impulse = -0.55;
  static const double terminalVel = 1.2;

  // Layout (normalized 0..1, y=0 top, y=1 bottom)
  static const double fairyX = 0.2;
  static const double fairyRadius = 0.03;
  static const double groundY = 0.88;
  static const double ceilingY = 0.0;

  // Rocks
  static const double rockSpeed = 0.28;
  static const double rockWidth = 0.1;
  static const double gapHalfHeight = 0.11;
  static const double rockSpacing = 0.45;
  static const int rockCount = 4;

  // State
  GameState state = GameState.menu;
  double fairyY = 0.45;
  double fairyVel = 0.0;
  int score = 0;
  double groundScroll = 0.0;
  double deathTimer = 0.0;
  final List<Rock> rocks = [];

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  final OpenGLBackend _ffi;

  SkyFairyGame(TickerProvider vsync, this._ffi) {
    _initRocks();
    _ticker = vsync.createTicker(_onTick)..start();
    pushUniforms();
  }

  void _initRocks() {
    rocks.clear();
    for (int i = 0; i < rockCount; i++) {
      rocks.add(Rock(
        x: 1.2 + i * rockSpacing,
        gapY: _randomGapY(),
        gapH: gapHalfHeight,
      ));
    }
  }

  double _randomGapY() {
    // Keep gap center between 0.2 and 0.7 (screen-space, y-down)
    return 0.2 + (_lcgNext() % 500) / 1000.0;
  }

  int _lcgState = 42;
  int _lcgNext() {
    _lcgState = (_lcgState * 1103515245 + 12345) & 0x7fffffff;
    return _lcgState;
  }

  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _lastElapsed).inMicroseconds / Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1) {
      pushUniforms();
      return;
    }

    switch (state) {
      case GameState.menu:
        // Gentle bob
        fairyY = 0.45 + 0.02 * _sin(elapsed.inMilliseconds / 400.0);
        groundScroll += rockSpeed * 0.5 * dt;
        break;
      case GameState.playing:
        _updatePlaying(dt);
        break;
      case GameState.dead:
        deathTimer += dt;
        // Let fairy fall after death
        fairyVel += gravity * dt;
        fairyY += fairyVel * dt;
        if (fairyY > groundY) fairyY = groundY;
        break;
    }
    pushUniforms();
  }

  void _updatePlaying(double dt) {
    // Gravity (y-down: positive vel = falling)
    fairyVel += gravity * dt;
    if (fairyVel > terminalVel) fairyVel = terminalVel;
    fairyY += fairyVel * dt;

    // Ground / ceiling collision
    if (fairyY > groundY - fairyRadius) {
      _die();
      return;
    }
    if (fairyY < ceilingY + fairyRadius) {
      fairyY = ceilingY + fairyRadius;
      fairyVel = 0;
    }

    // Scroll ground
    groundScroll += rockSpeed * dt;

    // Move rocks and check collisions
    for (final rock in rocks) {
      rock.x -= rockSpeed * dt;

      // Score when fairy passes rock center
      if (!rock.scored && rock.x + rockWidth * 0.5 < fairyX) {
        rock.scored = true;
        score++;
      }

      // Recycle rocks that go off-screen left
      if (rock.x < -rockWidth) {
        rock.x += rockCount * rockSpacing;
        rock.gapY = _randomGapY();
        rock.scored = false;
      }

      // Collision: fairy circle vs top/bottom rock rects
      if (_collidesWithRock(rock)) {
        _die();
        return;
      }
    }
  }

  bool _collidesWithRock(Rock rock) {
    final rockLeft = rock.x;
    final rockRight = rock.x + rockWidth;

    // Only check if fairy is horizontally overlapping
    if (fairyX + fairyRadius < rockLeft || fairyX - fairyRadius > rockRight) {
      return false;
    }

    // Top rock: from y=0 to gapY - gapH
    final topBottom = rock.gapY - rock.gapH;
    if (fairyY - fairyRadius < topBottom) return true;

    // Bottom rock: from gapY + gapH to groundY
    final bottomTop = rock.gapY + rock.gapH;
    if (fairyY + fairyRadius > bottomTop) return true;

    return false;
  }

  void _die() {
    state = GameState.dead;
    deathTimer = 0.0;
    // Small upward bump on death
    fairyVel = impulse * 0.4;
  }

  void tap() {
    switch (state) {
      case GameState.menu:
        state = GameState.playing;
        fairyY = 0.45;
        fairyVel = impulse;
        score = 0;
        _initRocks();
        break;
      case GameState.playing:
        fairyVel = impulse;
        break;
      case GameState.dead:
        if (deathTimer > 0.5) {
          state = GameState.menu;
          fairyY = 0.45;
          fairyVel = 0;
          score = 0;
          groundScroll = 0;
          _initRocks();
        }
        break;
    }
  }

  void pushUniforms() {
    final stateVal = state == GameState.menu
        ? 0.0
        : state == GameState.playing
            ? 1.0
            : 2.0;

    _ffi.setVec4Uniform('uGame', [stateVal, score.toDouble(), fairyY, fairyVel]);

    for (int i = 0; i < rockCount && i < 4; i++) {
      final r = rocks[i];
      final w = i == 0 ? groundScroll : 0.0;
      _ffi.setVec4Uniform('uRock$i', [r.x, r.gapY, r.gapH, w]);
    }
  }

  void dispose() {
    _ticker.dispose();
  }

  // Simple sin approximation to avoid dart:math import for just this
  static double _sin(double x) {
    x = x % (2 * 3.14159265);
    // Bhaskara I approximation
    if (x < 0) x += 2 * 3.14159265;
    if (x > 3.14159265) return -_sinHelper(x - 3.14159265);
    return _sinHelper(x);
  }

  static double _sinHelper(double x) {
    return 16 * x * (3.14159265 - x) /
        (5 * 3.14159265 * 3.14159265 - 4 * x * (3.14159265 - x));
  }
}
