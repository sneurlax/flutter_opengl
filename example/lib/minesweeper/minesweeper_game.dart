import 'dart:collection';
import 'package:flutter/scheduler.dart';
import 'package:flutter_opengl/flutter_opengl.dart';

enum MinesweeperState { ready, playing, won, lost }

class MinesweeperGame {
  static const int gridSize = 10;
  static const int mineCount = 15;

  MinesweeperState state = MinesweeperState.ready;
  double timer = 0.0;

  // Grid data
  final List<List<bool>> mines =
      List.generate(gridSize, (_) => List.filled(gridSize, false));
  final List<List<int>> adjacent =
      List.generate(gridSize, (_) => List.filled(gridSize, 0));
  // 0=hidden, 1=revealed, 2=flagged
  final List<List<int>> tileState =
      List.generate(gridSize, (_) => List.filled(gridSize, 0));

  int tapCol = -1;
  int tapRow = -1;
  int deathCol = -1;
  int deathRow = -1;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  final OpenGLBackend _ffi;

  int _lcgState = 12345;

  MinesweeperGame(TickerProvider vsync, this._ffi) {
    _ticker = vsync.createTicker(_onTick)..start();
    pushUniforms();
  }

  int _lcgNext() {
    _lcgState = (_lcgState * 1103515245 + 12345) & 0x7fffffff;
    return _lcgState;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1) {
      pushUniforms();
      return;
    }

    if (state == MinesweeperState.playing) {
      timer += dt;
    }

    pushUniforms();
  }

  void _placeMines(int safeRow, int safeCol) {
    // Clear
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        mines[r][c] = false;
        adjacent[r][c] = 0;
        tileState[r][c] = 0;
      }
    }

    int placed = 0;
    while (placed < mineCount) {
      int r = _lcgNext() % gridSize;
      int c = _lcgNext() % gridSize;

      // Skip 3x3 safe zone around first click
      if ((r - safeRow).abs() <= 1 && (c - safeCol).abs() <= 1) continue;
      if (mines[r][c]) continue;

      mines[r][c] = true;
      placed++;
    }

    // Compute adjacency counts
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (mines[r][c]) continue;
        int count = 0;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            int nr = r + dr, nc = c + dc;
            if (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
              if (mines[nr][nc]) count++;
            }
          }
        }
        adjacent[r][c] = count;
      }
    }
  }

  void reveal(int row, int col) {
    if (row < 0 || row >= gridSize || col < 0 || col >= gridSize) return;

    if (state == MinesweeperState.won || state == MinesweeperState.lost) {
      // Tap to restart
      _reset();
      return;
    }

    if (state == MinesweeperState.ready) {
      _placeMines(row, col);
      state = MinesweeperState.playing;
      timer = 0.0;
    }

    if (tileState[row][col] != 0) return; // already revealed or flagged

    tapCol = col;
    tapRow = row;

    if (mines[row][col]) {
      // Hit a mine
      tileState[row][col] = 1;
      deathCol = col;
      deathRow = row;
      state = MinesweeperState.lost;
      // Reveal all mines
      for (int r = 0; r < gridSize; r++) {
        for (int c = 0; c < gridSize; c++) {
          if (mines[r][c]) tileState[r][c] = 1;
        }
      }
      return;
    }

    // Flood-fill reveal for empty cells
    _floodReveal(row, col);
    _checkWin();
  }

  void _floodReveal(int startRow, int startCol) {
    final queue = Queue<int>();
    queue.add(startRow * gridSize + startCol);
    tileState[startRow][startCol] = 1;

    while (queue.isNotEmpty) {
      int idx = queue.removeFirst();
      int r = idx ~/ gridSize;
      int c = idx % gridSize;

      if (adjacent[r][c] > 0) continue; // stop at numbered cells

      for (int dr = -1; dr <= 1; dr++) {
        for (int dc = -1; dc <= 1; dc++) {
          int nr = r + dr, nc = c + dc;
          if (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
            if (tileState[nr][nc] == 0 && !mines[nr][nc]) {
              tileState[nr][nc] = 1;
              queue.add(nr * gridSize + nc);
            }
          }
        }
      }
    }
  }

  void _checkWin() {
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (!mines[r][c] && tileState[r][c] != 1) return;
      }
    }
    state = MinesweeperState.won;
  }

  void toggleFlag(int row, int col) {
    if (row < 0 || row >= gridSize || col < 0 || col >= gridSize) return;
    if (state != MinesweeperState.playing) return;

    if (tileState[row][col] == 0) {
      tileState[row][col] = 2; // flag
    } else if (tileState[row][col] == 2) {
      tileState[row][col] = 0; // unflag
    }
  }

  void _reset() {
    state = MinesweeperState.ready;
    timer = 0.0;
    tapCol = -1;
    tapRow = -1;
    deathCol = -1;
    deathRow = -1;
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        mines[r][c] = false;
        adjacent[r][c] = 0;
        tileState[r][c] = 0;
      }
    }
  }

  // Convert screen position to grid cell
  // Returns (col, row) or (-1,-1) if outside grid
  List<int> cellFromPosition(double localX, double localY, double width,
      double height) {
    double uvX = localX / width;
    double uvY = localY / height;

    double hudH = 0.08;
    double gridTop = hudH + 0.01;
    double gridBot = 0.99;
    double gridLeft = 0.005;
    double gridRight = 0.995;
    double cellSz = (gridRight - gridLeft) / 10.0;
    double cellSzY = (gridBot - gridTop) / 10.0;
    cellSz = cellSz < cellSzY ? cellSz : cellSzY;

    double totalW = cellSz * 10.0;
    double totalH = cellSz * 10.0;
    double gx0 = (1.0 - totalW) * 0.5;
    double gy0 = gridTop + ((gridBot - gridTop) - totalH) * 0.5;

    double relX = (uvX - gx0) / cellSz;
    double relY = (uvY - gy0) / cellSz;

    int col = relX.floor();
    int row = relY.floor();

    if (col < 0 || col >= gridSize || row < 0 || row >= gridSize) {
      return [-1, -1];
    }
    return [col, row];
  }

  int get flagCount {
    int count = 0;
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (tileState[r][c] == 2) count++;
      }
    }
    return count;
  }

  void pushUniforms() {
    double stateVal;
    switch (state) {
      case MinesweeperState.ready:
        stateVal = 0.0;
        break;
      case MinesweeperState.playing:
        stateVal = 1.0;
        break;
      case MinesweeperState.won:
        stateVal = 2.0;
        break;
      case MinesweeperState.lost:
        stateVal = 3.0;
        break;
    }

    _ffi.setVec4Uniform(
        'uGame', [stateVal, timer, flagCount.toDouble(), 0.0]);

    // Pack rows
    for (int r = 0; r < gridSize; r++) {
      List<double> packed = [0.0, 0.0, 0.0, 0.0];

      for (int c = 0; c < gridSize; c++) {
        int adj = adjacent[r][c] & 0xF;
        int mine = mines[r][c] ? 1 : 0;
        int ts = tileState[r][c] & 3;
        int val = adj | (mine << 4) | (ts << 5);

        if (c < 3) {
          packed[0] = (packed[0].toInt() | (val << (c * 7))).toDouble();
        } else if (c < 6) {
          packed[1] =
              (packed[1].toInt() | (val << ((c - 3) * 7))).toDouble();
        } else if (c < 9) {
          packed[2] =
              (packed[2].toInt() | (val << ((c - 6) * 7))).toDouble();
        } else {
          packed[3] = val.toDouble();
        }
      }

      _ffi.setVec4Uniform('uRow$r', packed);
    }

    _ffi.setVec4Uniform('uHighlight', [
      tapCol.toDouble(),
      tapRow.toDouble(),
      deathCol.toDouble(),
      deathRow.toDouble()
    ]);
  }

  void dispose() {
    _ticker.dispose();
  }
}
