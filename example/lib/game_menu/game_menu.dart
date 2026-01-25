import 'package:flutter/cupertino.dart';

import 'all_games.dart';

class GameMenu extends StatelessWidget {
  const GameMenu({super.key});

  static const title = 'Mini Games';

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text(title),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            children: [
              ...allGames().map((entry) {
                return CupertinoButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (ctx) {
                          return CupertinoPageScaffold(
                            navigationBar: CupertinoNavigationBar(
                              middle: Text(entry.name),
                              previousPageTitle: title,
                            ),
                            child: entry.buildWidget(ctx),
                          );
                        },
                      ),
                    );
                  },
                  child: Text(entry.name),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
