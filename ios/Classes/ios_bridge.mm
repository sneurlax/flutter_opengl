#import <Flutter/Flutter.h>
#import "FlutterOpenglTexture.h"
#import <OpenGLES/EAGL.h>

// Define _IS_IOS_ before including common.h so we get the right struct
#ifndef _IS_IOS_
#define _IS_IOS_ 1
#endif

#include "../../src/common.h"

extern "C" uint8_t* iosGetTextureBuffer(OpenglPluginContext *ctx) {
    if (!ctx || !ctx->myTexture) return nullptr;
    FlutterOpenglTexture *tex = (__bridge FlutterOpenglTexture *)ctx->myTexture;
    return tex.buffer;
}

extern "C" void iosMarkTextureFrameAvailable(OpenglPluginContext *ctx) {
    if (!ctx || !ctx->textureRegistry) return;
    NSObject<FlutterTextureRegistry> *registry =
        (__bridge NSObject<FlutterTextureRegistry> *)ctx->textureRegistry;
    int64_t textureId = ctx->flutterTextureId;
    // textureFrameAvailable must be called on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [registry textureFrameAvailable:textureId];
    });
}

extern "C" void iosMakeContextCurrent(OpenglPluginContext *ctx) {
    if (!ctx || !ctx->eaglContext) return;
    EAGLContext *eagl = (__bridge EAGLContext *)ctx->eaglContext;
    [EAGLContext setCurrentContext:eagl];
}

extern "C" void iosClearContext(void) {
    [EAGLContext setCurrentContext:nil];
}
