# flutter_opengl

A Flutter OpenGL ES plugin using a Texture() widget. Supports Android, iOS, Linux, macOS, Windows, and Web. Many shaders from ShaderToy.com can be copy/pasted.

## Getting Started

| Android | iOS | Linux | macOS | Windows | Web |
| ---- | ---- | ---- | ---- | ---- | ---- |
| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

![gif](https://github.com/alnitak/flutter_opengl/blob/master/images/flutter_opengl.gif?raw=true "Flutter OpenGL Demo")
![gif](https://github.com/alnitak/flutter_opengl/blob/master/images/flutter_OpenGL-video.gif?raw=true "Flutter OpenGL Demo")
![gif](https://github.com/alnitak/flutter_opengl/blob/master/images/flutter_OpenGL-textures.gif?raw=true "Flutter OpenGL Demo")

The main workflow of the plugin is:

- ask to native code with a MethodChannel for a texture ID
- use the texture ID in a Texture() widget
- set a vertex and a fragment sources
- start the renderer
- change shader sources on the fly

All functionalities, but the first call to the first method channel, use FFI calls.

The starting idea developing this plugin, was not just to use GLSL, but also take advantage of the wonderful [ShaderToy](https://www.shadertoy.com/) web site.

For now it's possible to copy/paste shaders from ShaderToy, but only those which have only one layer.

Be aware that on a real device, many shaders could be very slow because they are hungry of power and some others needs ES 3 and for now is not supported on Android (ie latest 3 shaders in the *lib/main_in_deep.dart* example).

***iResolution***, ***iTime***, ***iMouse***, ***iChannel[0-3]*** are supported, other uniforms can be added at run-time.

- ***iResolution*** is a vec3 uniform which represents the texture size
- ***iTime*** is a float which represents the time since the shader was created
- ***iMouse*** is a vec4 which the x and y values represent the coordinates where the mouse or the touch is grabbed hover the *Texture()* widget
- ***iChannel[0-3]*** Sampler2D uniform textures

### Simple example

```dart
SizedBox(
    width: 400,
    height: 300,
    child: FutureBuilder(
        /// The surface size identifies the real texture size and
        /// it is not related to the above SizedBox size
        future: OpenGLController().openglPlugin.createSurface(300, 200),
        builder: (_, snapshot) {
            if (snapshot.hasError || !snapshot.hasData) {
                return const SizedBox.shrink();
            }
            /// When the texture id is retrieved, it will be possible
            /// to start the renderer, set a shader and display it.

            /// Start renderer thread
            OpenGLController().openglFFI.startThread();

            /// Set the fragment shader
            OpenGLController().openglFFI.setShaderToy(fShader);

            /// build the texture widget
            return OpenGLTexture(id: snapshot.data!);
        },
    ),
)
```
Look at ***example/lib/main_in_deep.dart*** for a full fledged example.

Once the renderer is started all the below methods can be used via *OpenGLController().openglFFI*:

| method | description |
| ---- | ---- |
| bool **rendererStatus**() | Returns true if the texture has been created successfully via *OpenGLController().openglPlugin.createSurface()* |
| Size **getTextureSize**() | Get the size of the current texture. If not set it returns Size(-1, -1)|
| **startThread**() | Starts the drawing thread loop. |
| **stopThread**() | Delete shader, delete texture and stops the drawing thread loop. |
|String **setShader**(bool isContinuous, String vertexShader, String fragmentShader)|**isContinuous** not used yet.<br>**vertexShader** String of the vertex shader source. <br> **fragmentShader** String of the fragment shader source<br><br>returns the compiling shader error string or an empty string if no errors.|
| String **setShaderToy**(String fragmentShader) |Set the shader to be used in the current texture.<br>These are only fragment shaders taken from ShaderToy.com<br>Many of the shaders can be copy/pasted, but they must have only the "image" layer (ie no buffer).<br>Also many of them could be heavy for mobile devices (few FPS).<br><br>The uniforms actually available and automatically registered are:<br>float **iTime**<br>vec4 **iMouse**<br>vec3 **iResolution**<br>Sampler2D **iChannel[0-3]**|
| String **getVertexShader**() |Get current vertex shader text.|
| String **getFragmentShader**() |Get current fragment shader text.|
| **addShaderToyUniforms**() |add these uniforms:<br>vec4 **iMouse**<br>vec3 **iResolution**<br>float **iTime**<br>Sampler2D **iChannel[0-3]**<br>These uniforms are automatically set when using **setShaderToy()**|
|**setMousePosition**(Offset startingPos, Offset pos, PointerEventType eventType, Size twSize)|Set the **iMouse** uniform.<br>How to use the mouse input (only left button supported):<br>mouse.xy  = mouse position during last button down<br>abs(mouse.zw) = mouse position during last button click<br>sign(mouze.z)  = button is down<br>sign(mouze.w)  = button is clicked<br><br>This is automatically processed by **OpenGLTexture** widget<br><br>For reference:<br>https://www.shadertoy.com/view/llySRh<br>https://www.shadertoy.com/view/Mss3zH|
| double **getFps**() |Get current FPS (capped to 100).|
|bool **addBoolUniform**(String name, bool val)<br>bool **addIntUniform**(String name, int val)<br>bool **addFloatUniform**(String name, double val)<br>bool **addVec2Uniform**(String name, List`<double>` val)<br>bool **addVec3Uniform**(String name, List`<double>` val)<br>bool **addVec4Uniform**(String name, List`<double>` val)<br>bool **addMat2Uniform**(String name, List`<double>` val)<br>bool **addMat3Uniform**(String name, List`<double>` val)<br>bool **addMat4Uniform**(String name, List`<double>` val)| Add an uniforms.<br>Return true if succes or false if already added.|
|bool **addSampler2DUniform**(String name, int width, int height, Uint8List val)| Add a Sampler2D uniform. The raw image stored in *val* must be in RGBA32 format.|
|bool **replaceSampler2DUniform**(String name, int width, int height, Uint8List val)|Replace a Sampler2D uniform texture with another one with different size.|
|bool **setBoolUniform**(String name, bool val)<br>bool **setIntUniform**(String name, int val)<br>bool **setFloatUniform**(String name, double val)<br>bool **setVec2Uniform**(String name, List`<double>` val)<br>bool **setVec3Uniform**(String name, List`<double>` val)<br>bool **setVec4Uniform**(String name, List`<double>` val)<br>bool **setMat2Uniform**(String name, List`<double>` val)<br>bool **setMat3Uniform**(String name, List`<double>` val)<br>bool **setMat4Uniform**(String name, List`<double>` val)| Set value of an existing uniform. Return false if the uniform doesn't exist.|
|bool **setSampler2DUniform**(String name, Uint8List val)|Replace a texture with another image with the same size.<br>Be sure the *val* length is the same as the previously stored image with the uniform named *name*.|
|bool **startCaptureOnSampler2D**(String name, String completeFilePath)|Set Sampler2D uniform *name* with frames captured by OpenCV VideoCapture<br><br>*completeFilePath* can be:<br>- 'cam0' for webCam0<br>- 'cam1' for webCam1<br>- a complete local video file path<br><br>**Note**: this video capture is just for reference on how textures work in real time. Videos FPS are not precise and the camera on Android doesn't work.|
| bool **stopCapture**() | Stop capturing thread.|


# Setup

## Linux

Install the required development libraries:

```bash
sudo apt-get install -y libglew-dev libglm-dev libgtk-3-dev libegl-dev
```

OpenCV is optional. To build with OpenCV support (for video capture features), also install:

```bash
sudo apt-get install -y libopencv-dev
```

Then build with the OpenCV CMake flag:
```bash
flutter build linux --dart-define=WITH_OPENCV=true
```

**Note:** The plugin includes a bundled copy of GLM headers, so `libglm-dev` is optional if you prefer not to install it system-wide.

### Running with Impeller (preview)

Flutter on Linux uses the Skia renderer by default. Impeller is available as a preview:

```bash
flutter run -d linux --enable-impeller
```

The plugin uses `FlTextureGL` for zero-copy GPU texture sharing, which works with both Skia and Impeller backends.


## Windows

GLEW 2.2.0 and GLM headers are bundled with the plugin, so no manual dependency setup is required for a basic build.

OpenCV is optional. To build with OpenCV support, run `SCRIPTS\setupOpenCV-windows.bat` or manually download OpenCV from https://github.com/opencv/opencv/releases and extract it into the SCRIPTS directory.

## iOS

No additional setup is required. The plugin uses OpenGL ES 3.0 via the system-provided frameworks.

## macOS

No additional setup is required. The plugin uses CGL for the OpenGL context and integrates via FlutterTexture.

## Web

The plugin uses a WebGL2 rendering backend. Your target browser must support **WebGL2**. All modern browsers (Chrome, Firefox, Safari 15+, Edge) support WebGL2.

## Android

The plugin uses a Rust native library. The following tools must be installed before building:

```bash
# Rust cross-compilation targets for Android ABIs
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android

# cargo-ndk (drives the NDK cross-compiler)
cargo install cargo-ndk
```

OpenCV is optional. To build with OpenCV support, run `SCRIPTS/setupOpenCV-android.sh` or manually download OpenCV from https://github.com/opencv/opencv/releases and copy the libs and include folders into `android/src/opencv`.

# Known Limitations
- OpenCV video capture is only available on Android, Linux, and Windows (not supported on Web, iOS, or macOS)
- OpenGL is deprecated by Apple on macOS and iOS in favor of Metal; the plugin suppresses deprecation warnings but future OS updates may affect compatibility
- Only single-layer ShaderToy shaders (Image tab) are supported; multi-pass shaders with buffers are not yet implemented
- On Android, OpenGL ES 2.0 is used; some shaders requiring ES 3.0 features may not work
