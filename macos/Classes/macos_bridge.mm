#import <FlutterMacOS/FlutterMacOS.h>
#import "FlutterOpenglTexture.h"

// Define _IS_MACOS_ before including common.h so we get the right struct
#ifndef _IS_MACOS_
#define _IS_MACOS_ 1
#endif

#include "../../src/common.h"

extern "C" uint8_t* macosGetTextureBuffer(OpenglPluginContext *ctx) {
    if (!ctx || !ctx->myTexture) return nullptr;
    FlutterOpenglTexture *tex = (__bridge FlutterOpenglTexture *)ctx->myTexture;
    return tex.buffer;
}

extern "C" void macosMarkTextureFrameAvailable(OpenglPluginContext *ctx) {
    if (!ctx || !ctx->textureRegistry) return;
    NSObject<FlutterTextureRegistry> *registry =
        (__bridge NSObject<FlutterTextureRegistry> *)ctx->textureRegistry;
    int64_t textureId = ctx->flutterTextureId;
    // textureFrameAvailable must be called on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [registry textureFrameAvailable:textureId];
    });
}
