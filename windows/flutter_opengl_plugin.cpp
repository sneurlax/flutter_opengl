#include "flutter_opengl_plugin.h"
#include "rust_bridge.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <iostream>

#include <GL/glew.h>

namespace flutter_opengl {

/* -----------------------------------------------------------------------
 * Static state
 * ----------------------------------------------------------------------- */

static flutter::PluginRegistrarWindows *g_registrar = nullptr;
static flutter::TextureRegistrar       *g_texture_registrar = nullptr;
static FlMyTextureGL                   *g_myTexture = nullptr;
static int64_t                          g_texture_id = 0;
static HWND                             g_hWnd = 0;
static HDC                              g_hdc = 0;
static HGLRC                            g_hrc = 0;
static unsigned int                     g_texture_name = 0;
static int                              g_width = 0;
static int                              g_height = 0;

static WindowsBridgeData                g_bridge_data = {0, 0, 0, nullptr, nullptr, 0};

/* -----------------------------------------------------------------------
 * WGL context setup
 * ----------------------------------------------------------------------- */

static GLint MySetPixelFormat()
{
    // https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-choosepixelformat
    static PIXELFORMATDESCRIPTOR pfd =
    {
        sizeof(PIXELFORMATDESCRIPTOR),  //  size of this pfd
        1,                     // version number
        PFD_DRAW_TO_WINDOW |   // support window
        PFD_SUPPORT_OPENGL |   // support OpenGL
        PFD_DOUBLEBUFFER,      // double buffered
        PFD_TYPE_RGBA,         // RGBA type
        24,                    // 24-bit color depth
        0, 0, 0, 0, 0, 0,     // color bits ignored
        0,                     // no alpha buffer
        0,                     // shift bit ignored
        0,                     // no accumulation buffer
        0, 0, 0, 0,           // accum bits ignored
        32,                    // 32-bit z-buffer
        0,                     // no stencil buffer
        0,                     // no auxiliary buffer
        PFD_MAIN_PLANE,        // main layer
        0,                     // reserved
        0, 0, 0               // layer masks ignored
    };

    GLint iPixelFormat;

    // get the device context's best, available pixel format match
    if ((iPixelFormat = ChoosePixelFormat(g_hdc, &pfd)) == 0)
    {
        std::cout << "ChoosePixelFormat Failed" << std::endl;
        return 0;
    }

    // make that match the device context's current pixel format
    if (SetPixelFormat(g_hdc, iPixelFormat, &pfd) == FALSE)
    {
        std::cout << "SetPixelFormat Failed" << std::endl;
        return 0;
    }

    if ((g_hrc = wglCreateContext(g_hdc)) == NULL)
    {
        std::cout << "wglCreateContext Failed" << std::endl;
        return 0;
    }

    if ((wglMakeCurrent(g_hdc, g_hrc)) == NULL)
    {
        std::cout << "wglMakeCurrent Failed" << std::endl;
        return 0;
    }

    return 1;
}

static void initGL()
{
    g_hWnd = g_registrar->GetView()->GetNativeWindow();
    /* Get the handle of the windows device context. */
    g_hdc = GetDC(g_hWnd);

    wglMakeCurrent(g_hdc, NULL);
    MySetPixelFormat();

    // Initialize GL
    glewExperimental = GL_TRUE;
    GLenum err = glewInit();
    if (GLEW_OK != err)
    {
        /* Problem: glewInit failed, something is seriously wrong. */
        std::cout << "Error: " << glewGetErrorString(err) << std::endl;
        return;
    }
}

/* -----------------------------------------------------------------------
 * Plugin registration
 * ----------------------------------------------------------------------- */

void FlutterOpenglPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "flutter_opengl_plugin",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterOpenglPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  g_registrar = registrar;
  g_texture_registrar = registrar->texture_registrar();

  registrar->AddPlugin(std::move(plugin));
}

FlutterOpenglPlugin::FlutterOpenglPlugin() {}

FlutterOpenglPlugin::~FlutterOpenglPlugin() {
    deleteRenderer();
}

/* -----------------------------------------------------------------------
 * Method call handler
 * ----------------------------------------------------------------------- */

void FlutterOpenglPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  if (method_call.method_name().compare("createSurface") == 0) {
    flutter::EncodableMap arguments = std::get<flutter::EncodableMap>(*method_call.arguments());

    g_width = std::get<int>(arguments[flutter::EncodableValue("width")]);
    g_height = std::get<int>(arguments[flutter::EncodableValue("height")]);

    // Clean up previous resources if any
    if (getRenderer() != nullptr)
        stopThread();

    g_hWnd = g_registrar->GetView()->GetNativeWindow();

    // Initialize the WGL context
    initGL();

    // Create GL texture for FBO attachment
    glGenTextures(1, &g_texture_name);
    glBindTexture(GL_TEXTURE_2D, g_texture_name);

    // Clean up previous Flutter texture
    if (g_myTexture != nullptr) {
        delete g_myTexture;
        g_myTexture = nullptr;
    }

    // Create the Flutter pixel buffer texture
    g_myTexture = new FlMyTextureGL(g_texture_registrar, g_width, g_height);
    g_texture_id = g_myTexture->texture_id();

    // Clear the GL context before handing off to Rust
    wglMakeCurrent(NULL, NULL);

    // Populate the bridge data for Rust callbacks
    g_bridge_data.hwnd              = g_hWnd;
    g_bridge_data.hdc               = g_hdc;
    g_bridge_data.hrc               = g_hrc;
    g_bridge_data.texture_registrar = g_texture_registrar;
    g_bridge_data.my_texture        = g_myTexture;
    g_bridge_data.texture_id        = g_texture_id;

    PlatformContext ctx = windows_create_platform_context(
        &g_bridge_data, g_width, g_height, g_texture_name);
    createRenderer(&ctx);

    result->Success(flutter::EncodableValue(g_texture_id));

  } else {
    result->NotImplemented();
  }
}

}  // namespace flutter_opengl
