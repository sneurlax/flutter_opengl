import 'package:flutter/scheduler.dart';
import 'package:glow/glow.dart';

enum MemoryState { reveal, playing, mismatchWait, levelComplete, gameOver }

class MemoryGame {
  // Level configs: (cols, rows)
  static const List<List<int>> levels = [
    [4, 2],
    [5, 2],
    [4, 3],
    [4, 4],
  ];

  static const double revealDuration = 2.0;
  static const double mismatchDelay = 0.8;
  static const double levelCompleteDelay = 1.0;
  static const double countdownMax = 15.0;
  static const int maxLives = 3;

  MemoryState state = MemoryState.reveal;
  int level = 0; // 0-indexed
  int cols = 4;
  int rows = 2;
  int totalCards = 8;
  int score = 0;
  int lives = maxLives;
  double countdown = countdownMax;
  double revealTimer = revealDuration;
  double mismatchTimer = 0.0;
  double levelCompleteTimer = 0.0;

  // Card data
  List<int> symbols = []; // symbol ID per card (0-7)
  List<int> cardStates = []; // 0=faceDown, 1=faceUp, 2=matched

  int _firstCard = -1; // first selected card (game logic)
  int _mismatchA = -1; // cards to flip back after mismatch
  int _mismatchB = -1;
  int flipA = -1; // card being flip-animated (shader visual only)
  int flipB = -1;
  double flipProgress = 0.0;

  double touchX = 0.5;
  double touchY = 0.5;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  final OpenGLBackend _ffi;

  int _lcgState = 42;

  MemoryGame(TickerProvider vsync, this._ffi) {
    _startLevel();
    _ticker = vsync.createTicker(_onTick)..start();
    pushUniforms();
  }

  int _lcgNext() {
    _lcgState = (_lcgState * 1103515245 + 12345) & 0x7fffffff;
    return _lcgState;
  }

  void _startLevel() {
    if (level >= levels.length) {
      level = 0; // wrap around
      score += 200; // bonus for completing all
    }
    cols = levels[level][0];
    rows = levels[level][1];
    totalCards = cols * rows;

    // Create pairs
    int numPairs = totalCards ~/ 2;
    symbols = [];
    for (int i = 0; i < numPairs; i++) {
      int sym = i % 8;
      symbols.add(sym);
      symbols.add(sym);
    }

    // Fisher-Yates shuffle
    for (int i = symbols.length - 1; i > 0; i--) {
      int j = _lcgNext() % (i + 1);
      int tmp = symbols[i];
      symbols[i] = symbols[j];
      symbols[j] = tmp;
    }

    cardStates = List.filled(totalCards, 0);
    _firstCard = -1;
    _mismatchA = -1;
    _mismatchB = -1;
    flipA = -1;
    flipB = -1;
    flipProgress = 0.0;
    revealTimer = revealDuration;
    countdown = countdownMax;
    state = MemoryState.reveal;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1) {
      pushUniforms();
      return;
    }

    switch (state) {
      case MemoryState.reveal:
        revealTimer -= dt;
        if (revealTimer <= 0) {
          state = MemoryState.playing;
          revealTimer = 0;
        }
        break;

      case MemoryState.playing:
        countdown -= dt;
        if (countdown <= 0) {
          countdown = 0;
          lives--;
          if (lives <= 0) {
            state = MemoryState.gameOver;
          } else {
            // Reset level
            _startLevel();
          }
        }
        // Animate flip — clear indices once done so shader stops overriding
        if (flipA >= 0 || flipB >= 0) {
          flipProgress += dt * 4.0; // ~0.25s per flip
          if (flipProgress >= 1.0) {
            flipProgress = 0.0;
            flipA = -1;
            flipB = -1;
          }
        }
        break;

      case MemoryState.mismatchWait:
        mismatchTimer -= dt;
        if (mismatchTimer <= 0) {
          // Flip both back
          if (_mismatchA >= 0 && _mismatchA < totalCards) {
            cardStates[_mismatchA] = 0;
          }
          if (_mismatchB >= 0 && _mismatchB < totalCards) {
            cardStates[_mismatchB] = 0;
          }
          _mismatchA = -1;
          _mismatchB = -1;
          state = MemoryState.playing;
        }
        break;

      case MemoryState.levelComplete:
        levelCompleteTimer -= dt;
        if (levelCompleteTimer <= 0) {
          level++;
          _startLevel();
        }
        break;

      case MemoryState.gameOver:
        break;
    }

    pushUniforms();
  }

  void tapCard(int index) {
    if (index < 0 || index >= totalCards) return;

    if (state == MemoryState.gameOver) {
      // Restart
      level = 0;
      score = 0;
      lives = maxLives;
      _startLevel();
      return;
    }

    if (state != MemoryState.playing) return;
    if (cardStates[index] != 0) return; // already face up or matched

    if (_firstCard < 0) {
      // First card
      _firstCard = index;
      flipA = index;
      flipB = -1;
      cardStates[index] = 1;
      flipProgress = 0.0;
    } else if (index != _firstCard) {
      // Second card — show it immediately (no flip animation reset)
      cardStates[index] = 1;
      flipA = -1;
      flipB = -1;
      flipProgress = 0.0;

      // Check match
      if (symbols[_firstCard] == symbols[index]) {
        // Match!
        cardStates[_firstCard] = 2;
        cardStates[index] = 2;
        score += 10;
        _firstCard = -1;

        // Check level complete
        if (_allMatched()) {
          score += (level + 1) * 50;
          state = MemoryState.levelComplete;
          levelCompleteTimer = levelCompleteDelay;
        }
      } else {
        // Mismatch — wait then flip back
        _mismatchA = _firstCard;
        _mismatchB = index;
        _firstCard = -1;
        lives--;
        if (lives <= 0) {
          state = MemoryState.gameOver;
        } else {
          state = MemoryState.mismatchWait;
          mismatchTimer = mismatchDelay;
        }
      }
    }
  }

  bool _allMatched() {
    for (int i = 0; i < totalCards; i++) {
      if (cardStates[i] != 2) return false;
    }
    return true;
  }

  void setTouch(double x, double y) {
    touchX = x;
    touchY = y;
  }

  int cardIndexFromPosition(double localX, double localY, double width,
      double height) {
    double uvX = localX / width;
    double uvY = localY / height;

    double gridTop = 0.12;
    double gridBot = 0.98;
    double gridLeft = 0.05;
    double gridRight = 0.95;

    if (uvX < gridLeft || uvX > gridRight || uvY < gridTop || uvY > gridBot) {
      return -1;
    }

    double cellW = (gridRight - gridLeft) / cols;
    double cellH = (gridBot - gridTop) / rows;

    int cx = ((uvX - gridLeft) / cellW).floor();
    int cy = ((uvY - gridTop) / cellH).floor();

    if (cx < 0 || cx >= cols || cy < 0 || cy >= rows) return -1;

    int idx = cy * cols + cx;
    return idx < totalCards ? idx : -1;
  }

  void pushUniforms() {
    double stateVal;
    switch (state) {
      case MemoryState.reveal:
        stateVal = 0.0;
        break;
      case MemoryState.playing:
        stateVal = 1.0;
        break;
      case MemoryState.mismatchWait:
        stateVal = 2.0;
        break;
      case MemoryState.levelComplete:
        stateVal = 3.0;
        break;
      case MemoryState.gameOver:
        stateVal = 4.0;
        break;
    }

    _ffi.setVec4Uniform(
        'uGame', [stateVal, score.toDouble(), lives.toDouble(), countdown]);
    _ffi.setVec4Uniform('uGrid', [
      cols.toDouble(),
      rows.toDouble(),
      flipA.toDouble(),
      flipB.toDouble()
    ]);
    _ffi.setVec4Uniform('uAnim', [
      flipProgress,
      revealTimer,
      (level + 1).toDouble(),
      totalCards.toDouble()
    ]);

    // Pack card states: 4 per float, 2 bits each
    List<double> statesPacked = [0.0, 0.0, 0.0, 0.0];
    for (int i = 0; i < totalCards && i < 16; i++) {
      int slot = i ~/ 4;
      int local = i % 4;
      statesPacked[slot] =
          (statesPacked[slot].toInt() | (cardStates[i] << (local * 2)))
              .toDouble();
    }
    _ffi.setVec4Uniform('uStates', statesPacked);

    // Pack symbols: 4 per float, 3 bits each
    List<double> symsPacked = [0.0, 0.0, 0.0, 0.0];
    for (int i = 0; i < totalCards && i < 16; i++) {
      int slot = i ~/ 4;
      int local = i % 4;
      symsPacked[slot] =
          (symsPacked[slot].toInt() | (symbols[i] << (local * 3))).toDouble();
    }
    _ffi.setVec4Uniform('uSyms0', symsPacked);

    _ffi.setVec4Uniform('uTouch', [touchX, touchY, 0.0, 0.0]);
  }

  void dispose() {
    _ticker.dispose();
  }
}
