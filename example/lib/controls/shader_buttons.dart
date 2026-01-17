import 'package:flutter/material.dart';
import 'package:flutter_opengl/flutter_opengl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shadertoy.dart';
import '../states.dart';

/// Shader buttons (without texture)
///
class ShaderButtons extends ConsumerWidget {
  const ShaderButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeButtonId = ref.watch(stateShaderIndex);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Shader examples'),
        Wrap(
          alignment: WrapAlignment.center,
          runSpacing: 4,
          spacing: 4,
          children: [

            /// Build button for each fragments stored in [shaderToy] list
            /// Each button display also if a iChannelN is present
            /// displaying the iChannel number below the button number
            ...List.generate(shaderToy.length, (i) {
              bool hasIChannel0 =
                  shaderToy[i]['fragment']!.contains('iChannel0');
              bool hasIChannel1 =
                  shaderToy[i]['fragment']!.contains('iChannel1');
              bool hasIChannel2 =
                  shaderToy[i]['fragment']!.contains('iChannel2');
              bool hasIChannel3 =
                  shaderToy[i]['fragment']!.contains('iChannel3');
              return ElevatedButton(
                onPressed: () {
                  ref.read(stateUrl.notifier).state = shaderToy[i]['url']!;
                  OpenGLController().openglFFI.setShaderToy(
                        shaderToy[i]['fragment']!,
                      );
                  ref.read(stateShaderIndex.notifier).state = i;

                  /// reset bottom TextureChooser
                  ref.read(stateChannel0.notifier).state =
                      TextureParams().copyWith(assetsImage: '');
                  ref.read(stateChannel1.notifier).state =
                      TextureParams().copyWith(assetsImage: '');
                  ref.read(stateChannel2.notifier).state =
                      TextureParams().copyWith(assetsImage: '');
                  ref.read(stateChannel3.notifier).state =
                      TextureParams().copyWith(assetsImage: '');
                  /// stop capturing
                  if (ref.read(stateCaptureRunning)) {
                    OpenGLController().openglFFI.stopCapture();
                    ref.read(stateCaptureRunning.notifier).state = false;
                  }
                },
                style: ButtonStyle(
                  fixedSize: const WidgetStatePropertyAll(Size(65, 55)),
                  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4, vertical: 2)),
                  backgroundColor: i == activeButtonId
                      ? const WidgetStatePropertyAll(Colors.green)
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${i + 1}'),
                      Wrap(
                        children: [
                          if (hasIChannel0)
                            const Text('0 ', textScaler: TextScaler.linear(0.8)),
                          if (hasIChannel1)
                            const Text('1 ', textScaler: TextScaler.linear(0.8)),
                          if (hasIChannel2)
                            const Text('2 ', textScaler: TextScaler.linear(0.8)),
                          if (hasIChannel3)
                            const Text('3', textScaler: TextScaler.linear(0.8)),
                        ],
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ],
    );
  }
}
