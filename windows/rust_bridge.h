/* rust_bridge.h — Rust FFI bridge for Windows (WGL) */

#ifndef RUST_BRIDGE_H
#define RUST_BRIDGE_H

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/plugin_registrar_windows.h>
#include <stdint.h>

#include "fl_my_texture_gl.h"

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

    /* Whether the platform owns the texture storage (e.g. iOS CVTextureCache). */
    uint8_t  platform_owns_texture;

    /* Bytes per row of the pixel buffer (0 = tight packing at width*4). */
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

/* Rust FFI exports (flutter_opengl_rust.dll) */

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
    HWND                        hwnd;
    HDC                         hdc;
    HGLRC                       hrc;
    flutter::TextureRegistrar  *texture_registrar;
    FlMyTextureGL              *my_texture;
    int64_t                     texture_id;
} WindowsBridgeData;

/* Windows callbacks */

static inline void windows_make_current(void *user_data) {
    WindowsBridgeData *bd = (WindowsBridgeData *)user_data;
    if (bd && bd->hdc && bd->hrc) {
        wglMakeCurrent(bd->hdc, bd->hrc);
    }
}

static inline void windows_clear_context(void *user_data) {
    (void)user_data;
    wglMakeCurrent(NULL, NULL);
}

static inline unsigned char *windows_get_pixel_buffer(void *user_data) {
    WindowsBridgeData *bd = (WindowsBridgeData *)user_data;
    if (bd && bd->my_texture) {
        return bd->my_texture->buffer.data();
    }
    return NULL;
}

static inline void windows_mark_frame_available(void *user_data) {
    WindowsBridgeData *bd = (WindowsBridgeData *)user_data;
    if (bd && bd->texture_registrar && bd->my_texture) {
        /* Update the pixel buffer descriptor so Flutter can read it */
        bd->my_texture->Update();
    }
}

static inline int windows_swap_buffers(void *user_data) {
    WindowsBridgeData *bd = (WindowsBridgeData *)user_data;
    if (bd && bd->hdc) {
        return SwapBuffers(bd->hdc) ? 1 : 0;
    }
    return 0;
}

/* Try wglGetProcAddress, fall back to opengl32.dll. */
static inline const void *windows_load_gl_proc(const char *name) {
    const void *addr = (const void *)wglGetProcAddress(name);
    if (addr && addr != (const void *)0x1 &&
        addr != (const void *)0x2 &&
        addr != (const void *)0x3 &&
        addr != (const void *)(intptr_t)-1) {
        return addr;
    }
    /* Fallback: look up in opengl32.dll for core GL 1.1 symbols */
    HMODULE gl_module = GetModuleHandleA("opengl32.dll");
    if (gl_module) {
        addr = (const void *)GetProcAddress(gl_module, name);
    }
    return addr;
}

/* Populate a PlatformContext for Windows. */

static inline PlatformContext windows_create_platform_context(
        WindowsBridgeData *bridge_data,
        int32_t width,
        int32_t height,
        uint32_t texture_name) {
    PlatformContext ctx;

    ctx.make_current        = windows_make_current;
    ctx.clear_context       = windows_clear_context;
    ctx.get_pixel_buffer    = windows_get_pixel_buffer;
    ctx.mark_frame_available = windows_mark_frame_available;
    ctx.swap_buffers        = NULL;  /* Windows uses FBO + glReadPixels */
    ctx.load_gl_proc        = windows_load_gl_proc;
    ctx.user_data           = (void *)bridge_data;
    ctx.width               = width;
    ctx.height              = height;
    ctx.texture_name        = texture_name;
    ctx.uses_fbo            = 1;     /* FBO + glReadPixels into pixel buffer */
    ctx.platform_owns_texture = 0;
    ctx.bytes_per_row       = 0;

    return ctx;
}

#ifdef __cplusplus
}
#endif

#endif /* RUST_BRIDGE_H */
