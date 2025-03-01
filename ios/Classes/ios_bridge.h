#ifndef IOS_BRIDGE_H
#define IOS_BRIDGE_H

#ifdef _IS_IOS_

#include <stdint.h>

// Forward declare the context struct
struct flutter_opengl_plugin_context;

#ifdef __cplusplus
extern "C" {
#endif

// Get the raw pixel buffer pointer from the FlutterOpenglTexture
// stored in the context struct. Called from Shader::drawFrame().
uint8_t* iosGetTextureBuffer(flutter_opengl_plugin_context *ctx);

// Notify Flutter that a new frame is available.
// Called from Shader::drawFrame() after glReadPixels.
void iosMarkTextureFrameAvailable(flutter_opengl_plugin_context *ctx);

// Make the EAGL context current for the calling thread.
// Called from Shader/Renderer since they can't call ObjC directly.
void iosMakeContextCurrent(flutter_opengl_plugin_context *ctx);

// Clear the current EAGL context for the calling thread.
void iosClearContext(void);

#ifdef __cplusplus
}
#endif

#endif // _IS_IOS_
#endif // IOS_BRIDGE_H
