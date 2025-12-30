#include "include/flutter_opengl/flutter_opengl_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <flutter_linux/fl_view.h>
#include <sys/utsname.h>
#include <glib.h>

#include <GL/glew.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <cstring>
#include <iostream>
#include <memory>
#include <future>
#include <chrono>

#include "include/fl_my_texture_gl.h"
#include "../src/ffi.h"
#include "../src/common.h"


G_DEFINE_TYPE(FlutterOpenglPlugin, flutter_opengl_plugin, g_object_get_type())

#define EGL_EGLEXT_PROTOTYPES

static bool glew_initialized = false;

static bool ensure_glew_init() {
	if (glew_initialized)
		return true;
	glewExperimental = GL_TRUE;
	GLenum err = glewInit();
	if (GLEW_OK != err) {
		std::cout << "glewInit error: " << glewGetErrorString(err) << std::endl;
		return false;
	}
	glew_initialized = true;
	return true;
}

// Called when a method call is received from Flutter.
static void flutter_opengl_plugin_handle_method_call(
	FlutterOpenglPlugin *self,
	FlMethodCall *method_call)
{
	g_autoptr(FlMethodResponse) response = nullptr;

	const gchar *method = fl_method_call_get_name(method_call);
	FlValue *args = fl_method_call_get_args(method_call);

	if (strcmp(method, "createSurface") == 0)
	{
		int width = 0;
		int height = 0;
		FlValue *w = fl_value_lookup_string(args, "width");
		FlValue *h = fl_value_lookup_string(args, "height");
		if (w != nullptr)
			width = fl_value_get_int(w);
		if (h != nullptr)
			height = fl_value_get_int(h);
		if (width == 0 || height == 0)
		{
			response = FL_METHOD_RESPONSE(fl_method_error_response_new(
				"100",
				"MethodCall createSurface() called without passing width and height parameters!",
				nullptr));
		}
		else
		{
			if (self->context != nullptr &&
				self->myTexture != nullptr &&
				self->myTexture->width == width &&
				self->myTexture->height == height)
			{
				fl_texture_registrar_unregister_texture(self->texture_registrar, self->texture);
				if (getRenderer() != nullptr)
					stopThread();
			}

			GdkWindow *window = nullptr;
			window = gtk_widget_get_parent_window(GTK_WIDGET(self->fl_view));
			GError *error = NULL;
			self->context = gdk_window_create_gl_context(window, &error);
			if (self->context == nullptr) {
				std::cout << "Failed to create GL context: "
				          << (error ? error->message : "unknown") << std::endl;
				if (error) g_error_free(error);
				response = FL_METHOD_RESPONSE(fl_method_error_response_new(
					"101", "Failed to create GL context", nullptr));
				fl_method_call_respond(method_call, response, nullptr);
				return;
			}

			gdk_gl_context_make_current(self->context);

			// Initialize GLEW now that we have a current GL context
			if (!ensure_glew_init()) {
				gdk_gl_context_clear_current();
				response = FL_METHOD_RESPONSE(fl_method_error_response_new(
					"102", "Failed to initialize GLEW", nullptr));
				fl_method_call_respond(method_call, response, nullptr);
				return;
			}

			glGenTextures(1, &self->texture_name);
			glBindTexture(GL_TEXTURE_2D, self->texture_name);

			self->myTexture = fl_my_texture_gl_new(GL_TEXTURE_2D, self->texture_name, width, height);
			self->texture = FL_TEXTURE(self->myTexture);
			fl_texture_registrar_register_texture(self->texture_registrar, self->texture);
			fl_texture_registrar_mark_texture_frame_available(self->texture_registrar, self->texture);
			gdk_gl_context_clear_current();

			ctx_f.context = self->context;
			ctx_f.texture_name = self->texture_name;
			ctx_f.texture_registrar = self->texture_registrar;
			ctx_f.myTexture = self->myTexture;
			ctx_f.texture = self->texture;
			ctx_f.width = width;
			ctx_f.height = height;
			createRenderer(&ctx_f);

			g_autoptr(FlValue) result =
				fl_value_new_int(reinterpret_cast<int64_t>(self->texture));
			response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
		}

	}
	else
	{
		response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
	}

	fl_method_call_respond(method_call, response, nullptr);
}

static void flutter_opengl_plugin_dispose(GObject *object)
{
	G_OBJECT_CLASS(flutter_opengl_plugin_parent_class)->dispose(object);
}

static void flutter_opengl_plugin_class_init(FlutterOpenglPluginClass *klass)
{
	G_OBJECT_CLASS(klass)->dispose = flutter_opengl_plugin_dispose;
}

static void flutter_opengl_plugin_init(FlutterOpenglPlugin *self)
{
	self->context = nullptr;
	self->texture_registrar = nullptr;
	self->myTexture = nullptr;
	self->texture_name = 0;
	self->texture = nullptr;
	self->fl_view = nullptr;
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
						   gpointer user_data)
{
	FlutterOpenglPlugin *plugin = FLUTTER_OPENGL_PLUGIN(user_data);
	flutter_opengl_plugin_handle_method_call(plugin, method_call);
}

void flutter_opengl_plugin_register_with_registrar(FlPluginRegistrar *registrar)
{
	FlutterOpenglPlugin *plugin = FLUTTER_OPENGL_PLUGIN(
		g_object_new(flutter_opengl_plugin_get_type(), nullptr));

	FlView *fl_view = fl_plugin_registrar_get_view(registrar);
	plugin->fl_view = fl_view;
	plugin->texture_registrar =
		fl_plugin_registrar_get_texture_registrar(registrar);

	g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
	g_autoptr(FlMethodChannel) channel =
		fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
							  "flutter_opengl_plugin",
							  FL_METHOD_CODEC(codec));
	fl_method_channel_set_method_call_handler(
		channel,
		method_call_cb,
		g_object_ref(plugin),
		g_object_unref);

	g_object_unref(plugin);
}
