#include "include/fl_my_texture_gl.h"

#include <iostream>
#include <cstring>

G_DEFINE_TYPE(FlMyTextureGL,
              fl_my_texture_gl,
              fl_pixel_buffer_texture_get_type())

static gboolean fl_my_texture_gl_copy_pixels(FlPixelBufferTexture *texture,
                                              const uint8_t **out_buffer,
                                              uint32_t *width,
                                              uint32_t *height,
                                              GError **error)
{
  FlMyTextureGL* f = FL_MY_TEXTURE_GL(texture);
  *out_buffer = f->buffer;
  *width = f->width;
  *height = f->height;
  return TRUE;
}

FlMyTextureGL *fl_my_texture_gl_new(uint32_t target,
                                    uint32_t name,
                                    uint32_t width,
                                    uint32_t height)
{
  auto r = FL_MY_TEXTURE_GL(g_object_new(fl_my_texture_gl_get_type(), nullptr));
  r->target = target;
  r->name = name;
  r->width = width;
  r->height = height;
  r->buffer = new uint8_t[width * height * 4]();
  return r;
}

static void fl_my_texture_gl_dispose(GObject *object)
{
  FlMyTextureGL *self = FL_MY_TEXTURE_GL(object);
  delete[] self->buffer;
  self->buffer = nullptr;
  G_OBJECT_CLASS(fl_my_texture_gl_parent_class)->dispose(object);
}

static void fl_my_texture_gl_class_init(
    FlMyTextureGLClass *klass)
{
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      fl_my_texture_gl_copy_pixels;
  G_OBJECT_CLASS(klass)->dispose = fl_my_texture_gl_dispose;
}

static void fl_my_texture_gl_init(FlMyTextureGL *self)
{
  self->buffer = nullptr;
}
