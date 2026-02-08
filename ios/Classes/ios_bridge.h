/* ios_bridge.h — Rust FFI bridge for iOS (EAGL) */

#ifndef IOS_BRIDGE_H
#define IOS_BRIDGE_H

#import <Flutter/Flutter.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <CoreVideo/CoreVideo.h>
#include <dlfcn.h>
#include <stdint.h>

#import "FlutterOpenglTexture.h"

#ifdef __cplusplus
extern "C" {
#endif

/* -----------------------------------------------------------------------
 * PlatformContext
 *
 * Must match rust/src/platform.rs PlatformContext (#[repr(C)]).
 * ----------------------------------------------------------------------- */

typedef struct {
    /* Callbacks -- all receive user_data as their first argument */
    void  (*make_current)(void *user_data);
    void  (*clear_context)(void *user_data);
    unsigned char *(*get_pixel_buffer)(void *user_data);
    void  (*mark_frame_available)(void *user_data);
    int   (*swap_buffers)(void *user_data);       /* returns bool (0/1) */
    const void *(*load_gl_proc)(const char *name);

    /* Opaque pointer passed back to every callback */
    void *user_data;

    /* Texture / surface dimensions */
    int32_t  width;
    int32_t  height;

    /* GL texture name created by the platform plugin (FBO attachment target) */
    uint32_t texture_name;

    /* Whether this platform uses FBO + glReadPixels (1) or direct swap (0).
     * Stored as uint8_t to match Rust bool in repr(C). */
    uint8_t  uses_fbo;

    /* Whether the platform owns the texture storage (e.g. iOS CVTextureCache).
     * When 1, the Rust engine skips tex_image_2d and glReadPixels. */
    uint8_t  platform_owns_texture;

    /* Bytes per row of the pixel buffer.  IOSurface-backed CVPixelBuffers
     * may have row padding beyond width*4.  Rust uses this for
     * GL_PACK_ROW_LENGTH.  Set to 0 for tight (width*4) packing. */
    int32_t  bytes_per_row;
} PlatformContext;

/* -----------------------------------------------------------------------
 * UniformType enum -- must match rust/src/uniform.rs  UniformType (#[repr(i32)])
 * ----------------------------------------------------------------------- */

enum UniformType {
    UNIFORM_TYPE_BOOL       = 0,
    UNIFORM_TYPE_INT        = 1,
    UNIFORM_TYPE_FLOAT      = 2,
    UNIFORM_TYPE_VEC2       = 3,
    UNIFORM_TYPE_VEC3       = 4,
    UNIFORM_TYPE_VEC4       = 5,
    UNIFORM_TYPE_MAT2       = 6,
    UNIFORM_TYPE_MAT3       = 7,
    UNIFORM_TYPE_MAT4       = 8,
    UNIFORM_TYPE_SAMPLER2D  = 9,
};

/* Rust FFI exports (libflutter_opengl_rust.a) */

/* Renderer lifecycle */
extern void  createRenderer(PlatformContext *ctx);
extern void  deleteRenderer(void);
extern void *getRenderer(void);
extern int   rendererStatus(void);  /* returns bool */

/* Texture queries */
extern void  getTextureSize(int32_t *width, int32_t *height);

/* Thread control */
extern void  startThread(void);
extern void  stopThread(void);

/* Shader compilation */
extern const char *setShader(int isContinuous,
                             const char *vertexShader,
                             const char *fragmentShader);
extern const char *setShaderToy(const char *fragmentShader);

/* Shader source queries */
extern const char *getVertexShader(void);
extern const char *getFragmentShader(void);

/* ShaderToy uniforms */
extern void  addShaderToyUniforms(void);

/* Mouse / interaction */
extern void  setMousePosition(double posX, double posY,
                               double posZ, double posW,
                               double textureWidgetWidth,
                               double textureWidgetHeight);

/* FPS */
extern double getFPS(void);

/* Generic uniforms */
extern int   addUniform(const char *name, int32_t type, void *val);
extern int   removeUniform(const char *name);
extern int   setUniform(const char *name, void *val);

/* Sampler2D uniforms */
extern int   addSampler2DUniform(const char *name,
                                  int32_t width, int32_t height,
                                  void *val);
extern int   replaceSampler2DUniform(const char *name,
                                      int32_t width, int32_t height,
                                      void *val);

/* Capture stubs */
extern int   startCaptureOnSampler2D(const char *name,
                                      const char *completeFilePath);
extern int   stopCapture(void);

/* Miscellaneous */
extern void  nativeSurfaceSetClearColor(int32_t r, int32_t g,
                                         int32_t b, int32_t a);

/* Passed as user_data to PlatformContext callbacks. */

typedef struct {
    void *eagl_context;         /* EAGLContext* (__bridge void*) */
    void *texture_registry;     /* NSObject<FlutterTextureRegistry>* (__bridge void*) */
    void *my_texture;           /* FlutterOpenglTexture* (__bridge void*) */
    int64_t flutter_texture_id;
} IOSBridgeData;

/* iOS callbacks */

static inline void ios_make_current(void *user_data) {
    IOSBridgeData *bd = (IOSBridgeData *)user_data;
    if (bd && bd->eagl_context) {
        EAGLContext *ctx = (__bridge EAGLContext *)bd->eagl_context;
        [EAGLContext setCurrentContext:ctx];
    }
}

static inline void ios_clear_context(void *user_data) {
    (void)user_data;
    [EAGLContext setCurrentContext:nil];
}

static inline unsigned char *ios_get_pixel_buffer(void *user_data) {
    IOSBridgeData *bd = (IOSBridgeData *)user_data;
    if (bd && bd->my_texture) {
        FlutterOpenglTexture *tex = (__bridge FlutterOpenglTexture *)bd->my_texture;
        return tex.buffer;
    }
    return NULL;
}

static inline void ios_mark_frame_available(void *user_data) {
    IOSBridgeData *bd = (IOSBridgeData *)user_data;
    if (bd && bd->texture_registry) {
        NSObject<FlutterTextureRegistry> *registry =
            (__bridge NSObject<FlutterTextureRegistry> *)bd->texture_registry;
        int64_t textureId = bd->flutter_texture_id;
        /* textureFrameAvailable must be called on the main thread */
        dispatch_async(dispatch_get_main_queue(), ^{
            [registry textureFrameAvailable:textureId];
        });
    }
}

/* GL symbols are statically linked; use dlsym to look them up. */
static inline const void *ios_load_gl_proc(const char *name) {
    const void *addr = dlsym(RTLD_DEFAULT, name);
    return addr;
}

/* Populate a PlatformContext for iOS. */

static inline PlatformContext ios_create_platform_context(
        IOSBridgeData *bridge_data,
        int32_t width,
        int32_t height,
        uint32_t texture_name,
        int32_t bytes_per_row) {
    PlatformContext ctx;

    ctx.make_current        = ios_make_current;
    ctx.clear_context       = ios_clear_context;
    ctx.get_pixel_buffer    = ios_get_pixel_buffer;
    ctx.mark_frame_available = ios_mark_frame_available;
    ctx.swap_buffers        = NULL;  /* iOS uses FBO, not swap buffers */
    ctx.load_gl_proc        = ios_load_gl_proc;
    ctx.user_data           = (void *)bridge_data;
    ctx.width               = width;
    ctx.height              = height;
    ctx.texture_name        = texture_name;
    ctx.uses_fbo            = 1;     /* iOS uses FBO rendering */
    ctx.platform_owns_texture = 0;   /* Using FBO + glReadPixels path */
    ctx.bytes_per_row       = bytes_per_row;

    return ctx;
}

#ifdef __cplusplus
}
#endif

#endif /* IOS_BRIDGE_H */
