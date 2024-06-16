#import "FlutterOpenglPlugin.h"
#import "FlutterOpenglTexture.h"

#include <OpenGL/gl3.h>
#include <OpenGL/OpenGL.h>
#include <iostream>

#include "../../src/ffi.h"
#include "../../src/common.h"

@interface FlutterOpenglPlugin ()
@property (nonatomic, strong) NSObject<FlutterTextureRegistry> *textureRegistry;
@property (nonatomic, strong) FlutterOpenglTexture *myTexture;
@property (nonatomic, assign) CGLContextObj cglContext;
@property (nonatomic, assign) CGLPixelFormatObj cglPixelFormat;
@property (nonatomic, assign) GLuint textureName;
@property (nonatomic, assign) int64_t flutterTextureId;
@end

@implementation FlutterOpenglPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel =
        [FlutterMethodChannel methodChannelWithName:@"flutter_opengl_plugin"
                                    binaryMessenger:[registrar messenger]];
    FlutterOpenglPlugin *instance = [[FlutterOpenglPlugin alloc] init];
    instance.textureRegistry = [registrar textures];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call
                  result:(FlutterResult)result {
    if ([@"createSurface" isEqualToString:call.method]) {
        [self handleCreateSurface:call result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)handleCreateSurface:(FlutterMethodCall *)call
                     result:(FlutterResult)result {
    NSDictionary *args = call.arguments;
    NSNumber *widthNum = args[@"width"];
    NSNumber *heightNum = args[@"height"];

    if (!widthNum || !heightNum) {
        result([FlutterError errorWithCode:@"100"
                                   message:@"createSurface() called without width/height"
                                   details:nil]);
        return;
    }

    int width = [widthNum intValue];
    int height = [heightNum intValue];

    if (width == 0 || height == 0) {
        result([FlutterError errorWithCode:@"100"
                                   message:@"createSurface() called with zero width or height"
                                   details:nil]);
        return;
    }

    // Clean up previous surface if exists
    if (_myTexture != nil) {
        [_textureRegistry unregisterTexture:_flutterTextureId];
        _myTexture = nil;
        if (getRenderer() != nullptr)
            stopThread();
    }

    // Create CGL OpenGL context
    CGLPixelFormatAttribute attributes[] = {
        kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        kCGLPFAColorSize, (CGLPixelFormatAttribute)24,
        kCGLPFAAlphaSize, (CGLPixelFormatAttribute)8,
        kCGLPFADepthSize, (CGLPixelFormatAttribute)16,
        kCGLPFAAccelerated,
        kCGLPFADoubleBuffer,
        (CGLPixelFormatAttribute)0
    };

    GLint numPixelFormats = 0;
    CGLError err = CGLChoosePixelFormat(attributes, &_cglPixelFormat, &numPixelFormats);
    if (err != kCGLNoError || numPixelFormats == 0) {
        NSString *msg = [NSString stringWithFormat:@"CGLChoosePixelFormat failed: %s",
                         CGLErrorString(err)];
        std::cout << [msg UTF8String] << std::endl;
        result([FlutterError errorWithCode:@"101" message:msg details:nil]);
        return;
    }

    err = CGLCreateContext(_cglPixelFormat, NULL, &_cglContext);
    if (err != kCGLNoError) {
        NSString *msg = [NSString stringWithFormat:@"CGLCreateContext failed: %s",
                         CGLErrorString(err)];
        std::cout << [msg UTF8String] << std::endl;
        result([FlutterError errorWithCode:@"101" message:msg details:nil]);
        return;
    }

    CGLSetCurrentContext(_cglContext);

    // Generate GL texture
    glGenTextures(1, &_textureName);
    glBindTexture(GL_TEXTURE_2D, _textureName);

    // Create our pixel-buffer-backed texture object
    _myTexture = [[FlutterOpenglTexture alloc] initWithTarget:GL_TEXTURE_2D
                                                         name:_textureName
                                                        width:width
                                                       height:height];

    // Register with Flutter's texture registry
    _flutterTextureId = [_textureRegistry registerTexture:_myTexture];

    CGLSetCurrentContext(NULL);

    // Set up the context struct for the shared C++ renderer
    ctx_f.cglContext = _cglContext;
    ctx_f.texture_name = _textureName;
    ctx_f.textureRegistry = (__bridge void *)_textureRegistry;
    ctx_f.myTexture = (__bridge void *)_myTexture;
    ctx_f.flutterTextureId = _flutterTextureId;
    ctx_f.width = width;
    ctx_f.height = height;

    createRenderer(&ctx_f);

    result(@(_flutterTextureId));
}

@end
