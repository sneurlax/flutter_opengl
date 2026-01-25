import 'game_entry.dart';
import '../sky_fairy/sky_fairy_widget.dart';
import '../memory_game/memory_widget.dart';
import '../minesweeper/minesweeper_widget.dart';

List<GameEntry> allGames() => [
      GameEntry(name: 'Sky Fairy', buildWidget: (_) => const SkyFairyWidget()),
      GameEntry(
          name: 'Memory Game', buildWidget: (_) => const MemoryWidget()),
      GameEntry(
          name: 'Minesweeper', buildWidget: (_) => const MinesweeperWidget()),
    ];
