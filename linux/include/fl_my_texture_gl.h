#ifndef FLUTTER_MY_TEXTURE_H
#define FLUTTER_MY_TEXTURE_H

#include <gtk/gtk.h>
#include <glib-object.h>
#include "flutter_opengl/flutter_opengl_plugin.h"
#include <flutter_linux/flutter_linux.h>
#include <vector>

G_DECLARE_FINAL_TYPE(FlMyTextureGL,
                     fl_my_texture_gl,
                     FL,
                     MY_TEXTURE_GL,
                     FlPixelBufferTexture)

struct _FlMyTextureGL
{
    FlPixelBufferTexture parent_instance;
    uint32_t target;
    uint32_t name;
    uint32_t width;
    uint32_t height;
    uint8_t *buffer;
};


#define FLUTTER_OPENGL_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_opengl_plugin_get_type(), \
                              FlutterOpenglPlugin))

struct _FlutterOpenglPlugin
{
  GObject parent_instance;
  GdkGLContext *context;
  FlTextureRegistrar *texture_registrar;
  FlMyTextureGL *myTexture;
  unsigned int texture_name;
  FlTexture *texture;
  FlView *fl_view;
};


FlMyTextureGL *fl_my_texture_gl_new(uint32_t target,
                                    uint32_t name,
                                    uint32_t width,
                                    uint32_t height);
#endif // FLUTTER_MY_TEXTURE_H
