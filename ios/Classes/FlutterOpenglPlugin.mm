#import "FlutterOpenglPlugin.h"
#import "FlutterOpenglTexture.h"
#import "ios_bridge.h"

static IOSBridgeData g_bridge_data;

@interface FlutterOpenglPlugin ()
@property (nonatomic, strong) NSObject<FlutterTextureRegistry> *textureRegistry;
@property (nonatomic, strong) FlutterOpenglTexture *myTexture;
@property (nonatomic, strong) EAGLContext *eaglContext;
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
        if (getRenderer() != NULL)
            stopThread();
    }

    // Create EAGL OpenGL ES 3.0 context
    _eaglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!_eaglContext) {
        result([FlutterError errorWithCode:@"101"
                                   message:@"Failed to create EAGLContext (OpenGL ES 3.0)"
                                   details:nil]);
        return;
    }

    [EAGLContext setCurrentContext:_eaglContext];

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

    [EAGLContext setCurrentContext:nil];

    // Populate the bridge data struct for Rust callbacks
    g_bridge_data.eagl_context       = (__bridge void *)_eaglContext;
    g_bridge_data.texture_registry   = (__bridge void *)_textureRegistry;
    g_bridge_data.my_texture         = (__bridge void *)_myTexture;
    g_bridge_data.flutter_texture_id = _flutterTextureId;

    // Create the PlatformContext and pass it to the Rust renderer
    PlatformContext platformCtx = ios_create_platform_context(
        &g_bridge_data, width, height, _textureName);
    createRenderer(&platformCtx);

    result(@(_flutterTextureId));
}

@end
