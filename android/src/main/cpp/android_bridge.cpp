/*
 * android_bridge.cpp
 *
 * JNI bridge for the Flutter OpenGL plugin on Android.
 * Replaces the old ndk.cpp that used C++ engine sources directly.
 * Now delegates all rendering to the Rust shared library via the
 * PlatformContext / FFI interface defined in android_bridge.h.
 */

#include "android_bridge.h"

#define JNI_FUNC(X) JNIEXPORT Java_com_example_flutter_1opengl_FlutterOpenglPlugin_##X

static AndroidBridgeData g_bridge_data = {
    EGL_NO_DISPLAY,
    EGL_NO_CONTEXT,
    EGL_NO_SURFACE,
    NULL
};

/* -----------------------------------------------------------------------
 * JNI_OnLoad
 *
 * Called by the JVM when System.loadLibrary() loads this .so.
 * ----------------------------------------------------------------------- */

extern "C" jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    LOGD("JNI_OnLoad: Android bridge initialized");
    return JNI_VERSION_1_6;
}

/* -----------------------------------------------------------------------
 * nativeSetSurface
 *
 * Called from Java when the Flutter SurfaceTexture is ready.
 * Sets up EGL on the ANativeWindow and creates the Rust renderer.
 * ----------------------------------------------------------------------- */

extern "C" void JNI_FUNC(nativeSetSurface)(JNIEnv *jenv,
                                            jclass cls,
                                            jobject surface,
                                            jint width,
                                            jint height) {
    (void)cls;

    LOGD("nativeSetSurface: %dx%d", width, height);

    /* If there is already a renderer running, tear it down first */
    if (getRenderer() != NULL) {
        LOGD("nativeSetSurface: stopping previous renderer");
        stopThread();
    }

    /* Tear down any previous EGL state */
    android_destroy_egl(&g_bridge_data);

    /* Get the ANativeWindow from the Java Surface */
    ANativeWindow *window = ANativeWindow_fromSurface(jenv, surface);
    if (window == NULL) {
        LOGE("nativeSetSurface: ANativeWindow_fromSurface returned NULL");
        return;
    }

    /* Initialize EGL */
    if (!android_init_egl(&g_bridge_data, window, width, height)) {
        LOGE("nativeSetSurface: EGL initialization failed");
        return;
    }

    /* Clear the EGL context from this thread -- the Rust render thread will
     * make it current via the make_current callback. */
    eglMakeCurrent(g_bridge_data.display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                    EGL_NO_CONTEXT);

    /* Build the PlatformContext and hand it to the Rust renderer */
    PlatformContext ctx = android_create_platform_context(
        &g_bridge_data, width, height);
    createRenderer(&ctx);
    startThread();

    LOGD("nativeSetSurface: renderer created and render thread started");
}

/* -----------------------------------------------------------------------
 * nativeDestroyRenderer
 *
 * Optional: called from Java when the plugin is detached or the surface
 * is about to be destroyed.
 * ----------------------------------------------------------------------- */

extern "C" void JNI_FUNC(nativeDestroyRenderer)(JNIEnv *jenv,
                                                  jclass cls) {
    (void)jenv;
    (void)cls;

    LOGD("nativeDestroyRenderer");

    if (getRenderer() != NULL) {
        stopThread();
    }

    android_destroy_egl(&g_bridge_data);
}
