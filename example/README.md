# flutter_opengl example

Demonstrates real-time ShaderToy-compatible fragment shaders rendered via OpenGL
on all supported Flutter platforms (Linux, Windows, macOS, Android, iOS, Web).

## Running

### Simple demo (Star Nest shader)

```bash
flutter run -d linux    # or chrome, windows, macos, android, ios
```

Tap the floating action button to open the advanced view.

### Advanced demo (shader explorer)

```bash
flutter run -t lib/main_in_deep.dart -d linux
```

The advanced view provides:

- Shader switching between bundled ShaderToy examples
- Live shader editor with hot-reload
- iChannel texture inputs (image, video, camera)
- Video capture of rendered output
- Texture size controls and FPS display

## Platform notes

- Video capture and camera input require native platform support and are
  unavailable on web.
- Test tabs are hidden on web builds.
