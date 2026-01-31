/* android_bridge.h — Rust FFI bridge for Android (EGL) */

#ifndef ANDROID_BRIDGE_H
#define ANDROID_BRIDGE_H

#include <jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <stdint.h>
#include <string.h>

#define LOG_TAG "AndroidBridge"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

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

/* Rust FFI exports */

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
    EGLDisplay  display;
    EGLContext  context;
    EGLSurface  surface;
    ANativeWindow *window;
} AndroidBridgeData;

/* Android callbacks */

static inline void android_make_current(void *user_data) {
    AndroidBridgeData *bd = (AndroidBridgeData *)user_data;
    if (bd && bd->display != EGL_NO_DISPLAY &&
        bd->surface != EGL_NO_SURFACE &&
        bd->context != EGL_NO_CONTEXT) {
        if (!eglMakeCurrent(bd->display, bd->surface, bd->surface, bd->context)) {
            LOGE("eglMakeCurrent failed: 0x%x", eglGetError());
        }
    }
}

static inline void android_clear_context(void *user_data) {
    AndroidBridgeData *bd = (AndroidBridgeData *)user_data;
    if (bd && bd->display != EGL_NO_DISPLAY) {
        eglMakeCurrent(bd->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
}

static inline int android_swap_buffers(void *user_data) {
    AndroidBridgeData *bd = (AndroidBridgeData *)user_data;
    if (bd && bd->display != EGL_NO_DISPLAY && bd->surface != EGL_NO_SURFACE) {
        if (!eglSwapBuffers(bd->display, bd->surface)) {
            LOGE("eglSwapBuffers failed: 0x%x", eglGetError());
            return 0;
        }
        return 1;
    }
    return 0;
}

static inline unsigned char *android_get_pixel_buffer(void *user_data) {
    (void)user_data;
    return NULL;
}

static inline void android_mark_frame_available(void *user_data) {
    (void)user_data;
}

static inline const void *android_load_gl_proc(const char *name) {
    return (const void *)eglGetProcAddress(name);
}

/* Set up EGL display, context, and surface. Returns 1 on success. */

static inline int android_init_egl(AndroidBridgeData *bd,
                                    ANativeWindow *window,
                                    int width, int height) {
    const EGLint attribs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_BLUE_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_RED_SIZE, 8,
        EGL_NONE
    };
    EGLConfig config;
    EGLint numConfigs;
    EGLint format;
    EGLint majorVersion, minorVersion;

    bd->window = window;

    bd->display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (bd->display == EGL_NO_DISPLAY) {
        LOGE("eglGetDisplay failed");
        return 0;
    }

    if (!eglInitialize(bd->display, &majorVersion, &minorVersion)) {
        LOGE("eglInitialize failed: 0x%x", eglGetError());
        return 0;
    }

    LOGD("EGL version: %d.%d", majorVersion, minorVersion);

    if (!eglChooseConfig(bd->display, attribs, &config, 1, &numConfigs)) {
        LOGE("eglChooseConfig failed: 0x%x", eglGetError());
        return 0;
    }

    if (!eglGetConfigAttrib(bd->display, config, EGL_NATIVE_VISUAL_ID, &format)) {
        LOGE("eglGetConfigAttrib failed: 0x%x", eglGetError());
        return 0;
    }

    ANativeWindow_setBuffersGeometry(window, width, height, format);

    bd->surface = eglCreateWindowSurface(bd->display, config, window, 0);
    if (bd->surface == EGL_NO_SURFACE) {
        LOGE("eglCreateWindowSurface failed: 0x%x", eglGetError());
        return 0;
    }

    const EGLint context_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    bd->context = eglCreateContext(bd->display, config, EGL_NO_CONTEXT,
                                    context_attribs);
    if (bd->context == EGL_NO_CONTEXT) {
        LOGE("eglCreateContext failed: 0x%x", eglGetError());
        return 0;
    }

    if (!eglMakeCurrent(bd->display, bd->surface, bd->surface, bd->context)) {
        LOGE("eglMakeCurrent failed: 0x%x", eglGetError());
        return 0;
    }

    eglSwapInterval(bd->display, 1);

    LOGD("EGL initialized successfully (%dx%d)", width, height);
    return 1;
}

/* Tear down EGL. */

static inline void android_destroy_egl(AndroidBridgeData *bd) {
    if (bd->display != EGL_NO_DISPLAY) {
        eglMakeCurrent(bd->display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                        EGL_NO_CONTEXT);
    }
    if (bd->display != EGL_NO_DISPLAY && bd->context != EGL_NO_CONTEXT) {
        eglDestroyContext(bd->display, bd->context);
    }
    if (bd->display != EGL_NO_DISPLAY && bd->surface != EGL_NO_SURFACE) {
        eglDestroySurface(bd->display, bd->surface);
    }
    if (bd->display != EGL_NO_DISPLAY) {
        eglTerminate(bd->display);
    }

    bd->display = EGL_NO_DISPLAY;
    bd->context = EGL_NO_CONTEXT;
    bd->surface = EGL_NO_SURFACE;

    if (bd->window != NULL) {
        ANativeWindow_release(bd->window);
        bd->window = NULL;
    }

    LOGD("EGL destroyed");
}

/* Populate a PlatformContext for Android. */

static inline PlatformContext android_create_platform_context(
        AndroidBridgeData *bridge_data,
        int32_t width,
        int32_t height) {
    PlatformContext ctx;
    memset(&ctx, 0, sizeof(ctx));

    ctx.make_current        = android_make_current;
    ctx.clear_context       = android_clear_context;
    ctx.get_pixel_buffer    = android_get_pixel_buffer;
    ctx.mark_frame_available = android_mark_frame_available;
    ctx.swap_buffers        = android_swap_buffers;
    ctx.load_gl_proc        = android_load_gl_proc;
    ctx.user_data           = (void *)bridge_data;
    ctx.width               = width;
    ctx.height              = height;
    ctx.texture_name        = 0;    /* Android does not use FBO texture */
    ctx.uses_fbo            = 0;    /* Android uses swap buffers, not FBO */

    return ctx;
}

#ifdef __cplusplus
}
#endif

#endif /* ANDROID_BRIDGE_H */
