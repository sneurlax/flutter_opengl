import 'package:flutter_opengl/src/flutter_opengl_method_channel.dart';
import 'package:flutter_opengl/src/flutter_opengl_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final FlutterOpenglPlatform initialPlatform = FlutterOpenglPlatform.instance;

  test('$MethodChannelFlutterOpengl is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterOpengl>());
  });
}
