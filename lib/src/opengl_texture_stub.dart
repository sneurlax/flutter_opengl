import 'package:flutter/material.dart';

class OpenGLTexture extends StatelessWidget {
  final int id;

  const OpenGLTexture({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    throw UnsupportedError('OpenGLTexture is not supported on this platform.');
  }
}
