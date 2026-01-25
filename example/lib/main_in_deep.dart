import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_opengl/flutter_opengl.dart';
import 'package:flutter_opengl_example/controls/controls.dart';
import 'package:flutter_opengl_example/edit_shader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'game_menu/all_games.dart';
import 'shadertoy.dart';
import 'states.dart';
import 'test_widget.dart';

void main() {
  OpenGLController().initializeGL();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: const TextureAndTabs(),
    );
  }
}

class TextureAndTabs extends ConsumerStatefulWidget {
  const TextureAndTabs({super.key});

  @override
  ConsumerState<TextureAndTabs> createState() => _TextureAndTabsState();
}

class _TextureAndTabsState extends ConsumerState<TextureAndTabs> {
  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Permission.camera.request();
      await Permission.videos.request();
      await Permission.mediaLibrary.request();
      await Permission.accessMediaLocation.request();
    }

    final size = ref.read(stateTextureSize);
    final id = await OpenGLController().openglFFI.createSurface(
          size.width.toInt(),
          size.height.toInt(),
        );
    if (!mounted) return;
    ref.read(stateTextureCreated.notifier).state =
        OpenGLController().openglFFI.rendererStatus();
    ref.read(stateTextureId.notifier).state = id;

    OpenGLController().openglFFI.startThread();

    // Auto-load the first shader so the user sees something immediately
    if (shaderToy.isNotEmpty) {
      OpenGLController().openglFFI.setShaderToy(shaderToy[0]['fragment']!);
      ref.read(stateUrl.notifier).state = shaderToy[0]['url']!;
      ref.read(stateShaderIndex.notifier).state = 0;
    }
  }

  void _restartRenderer() {
    final ffi = OpenGLController().openglFFI;
    ffi.startThread();
    final idx = ref.read(stateShaderIndex);
    if (idx >= 0 && idx < shaderToy.length) {
      ffi.setShaderToy(shaderToy[idx]['fragment']!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textureSize = ref.watch(stateTextureSize);
    final textureId = ref.watch(stateTextureId);

    final tabs = <Widget>[
      const Tab(text: 'shaders'),
      const Tab(text: 'edit shader'),
      if (!kIsWeb) const Tab(text: 'test 1'),
      if (!kIsWeb) const Tab(text: 'test 2'),
      const Tab(text: 'games'),
    ];
    final tabViews = <Widget>[
      const Controls(),
      const EditShader(),
      if (!kIsWeb) const TestWidget(shaderToyCode: 'ls3cDB'),
      if (!kIsWeb) const TestWidget(shaderToyCode: 'XdXGR7'),
      _GamesTab(onRestart: _restartRenderer),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              /// FPS and ShaderToy URL text
              const UpperText(),
              const SizedBox(height: 8),

              /// TEXTURE
              AspectRatio(
                  aspectRatio: textureSize.width / textureSize.height,
                  child: textureId == -1
                      ? const ColoredBox(color: Colors.black)
                      : OpenGLTexture(id: textureId)),

              SizedBox(
                height: 40,
                child: TabBar(
                  isScrollable: true,
                  tabs: tabs,
                ),
              ),

              const SizedBox(height: 12),

              /// TABS
              Expanded(
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: tabViews,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GamesTab extends StatelessWidget {
  const _GamesTab({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final games = allGames();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: games.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ElevatedButton(
              onPressed: () {
                OpenGLController().openglFFI.stopThread();
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (ctx) => Scaffold(
                          appBar: AppBar(title: Text(entry.name)),
                          body: entry.buildWidget(ctx),
                        ),
                      ),
                    )
                    .then((_) => onRestart());
              },
              child: Text(entry.name),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// FPS, texture size and shader URL
///
class UpperText extends ConsumerWidget {
  const UpperText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fps = ref.watch(stateFPS);
    final shaderUrl = ref.watch(stateUrl);
    final textureSize = ref.watch(stateTextureSize);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 30,
      children: [
        Text(
            '${fps.toStringAsFixed(1)} FPS\n'
            '${textureSize.width.toInt()} x '
            '${textureSize.height.toInt()}',
            textAlign: TextAlign.center,
            textScaler: TextScaler.linear(1.2)),
        if (shaderUrl.isNotEmpty)
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: shaderUrl,
                  style: const TextStyle(
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.bold),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      launchUrl(Uri.parse(shaderUrl));
                    },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
