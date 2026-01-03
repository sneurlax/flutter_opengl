#ifndef MACOS_BRIDGE_H
#define MACOS_BRIDGE_H

#ifdef _IS_MACOS_

#include <stdint.h>

// Forward declare the context struct
struct flutter_opengl_plugin_context;

#ifdef __cplusplus
extern "C" {
#endif

// Get the raw pixel buffer pointer from the FlutterOpenglTexture
// stored in the context struct. Called from Shader::drawFrame().
uint8_t* macosGetTextureBuffer(flutter_opengl_plugin_context *ctx);

// Notify Flutter that a new frame is available.
// Called from Shader::drawFrame() after glReadPixels.
void macosMarkTextureFrameAvailable(flutter_opengl_plugin_context *ctx);

#ifdef __cplusplus
}
#endif

#endif // _IS_MACOS_
#endif // MACOS_BRIDGE_H
