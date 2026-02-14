use glow::HasContext;

#[cfg(not(target_arch = "wasm32"))]
use crate::platform::PlatformContext;
use crate::sampler::Sampler2D;
use crate::uniform::{UniformQueue, UniformType};

const QUAD_VERTICES: [f32; 18] = [
    -1.0, -1.0, 0.0,
    -1.0,  1.0, 0.0,
     1.0, -1.0, 0.0,
    -1.0,  1.0, 0.0,
     1.0,  1.0, 0.0,
     1.0, -1.0, 0.0,
];

pub struct Shader {
    gl: glow::Context,
    program: Option<glow::Program>,
    vao: Option<glow::VertexArray>,
    vbo: Option<glow::Buffer>,
    fbo: Option<glow::Framebuffer>,
    width: i32,
    height: i32,
    #[cfg(not(target_arch = "wasm32"))]
    start_instant: Option<std::time::Instant>,
    #[cfg(target_arch = "wasm32")]
    start_instant: Option<()>,
    is_continuous: bool,
    uniforms: UniformQueue,
    vertex_source: String,
    fragment_source: String,
    compile_error: String,
    texture_name: u32,
    uses_fbo: bool,
    platform_owns_texture: bool,
    bytes_per_row: i32,
}

impl Shader {
    pub fn new(gl: glow::Context, width: i32, height: i32, texture_name: u32, uses_fbo: bool, platform_owns_texture: bool, bytes_per_row: i32) -> Self {
        Self {
            gl,
            program: None,
            vao: None,
            vbo: None,
            fbo: None,
            width,
            height,
            start_instant: None,
            is_continuous: false,
            uniforms: UniformQueue::new(),
            vertex_source: String::new(),
            fragment_source: String::new(),
            compile_error: String::new(),
            texture_name,
            uses_fbo,
            platform_owns_texture,
            bytes_per_row,
        }
    }

    pub fn set_shaders_text(&mut self, vertex: String, fragment: String) {
        self.vertex_source = vertex;
        self.fragment_source = fragment;
    }

    pub fn set_shaders_size(&mut self, w: i32, h: i32) {
        self.width = w;
        self.height = h;
    }

    pub fn set_is_continuous(&mut self, c: bool) {
        self.is_continuous = c;
    }

    pub fn is_continuous(&self) -> bool {
        self.is_continuous
    }

    pub fn is_valid(&self) -> bool {
        self.program.is_some()
    }

    pub fn width(&self) -> i32 {
        self.width
    }

    pub fn height(&self) -> i32 {
        self.height
    }

    pub fn uniforms(&self) -> &UniformQueue {
        &self.uniforms
    }

    pub fn uniforms_mut(&mut self) -> &mut UniformQueue {
        &mut self.uniforms
    }

    pub fn vertex_source(&self) -> &str {
        &self.vertex_source
    }

    pub fn fragment_source(&self) -> &str {
        &self.fragment_source
    }

    pub fn compile_error(&self) -> &str {
        &self.compile_error
    }

    pub fn gl(&self) -> &glow::Context {
        &self.gl
    }

    pub fn program(&self) -> Option<glow::Program> {
        self.program
    }

    /// Replace sampler2D data and re-upload the texture to the GPU using the
    /// shader's own glow context. This avoids creating a separate glow context
    /// which on WebGL2 would have a different slotmap, making texture keys
    /// invalid.
    pub fn replace_and_upload_sampler2d(
        &mut self,
        name: &str,
        w: i32,
        h: i32,
        data: &[u8],
    ) -> bool {
        if !self.uniforms.replace_sampler2d(name, w, h, data) {
            return false;
        }
        if let Some(sampler) = self.uniforms.get_sampler2d(name) {
            let n = sampler.n_texture;
            if n != -1 {
                sampler.gen_texture(&self.gl, n);
            }
        }
        true
    }

    /// Remove a uniform, deleting its GL texture (if sampler) using the
    /// shader's own glow context.
    pub fn remove_uniform(&mut self, name: &str, renderer_running: bool) -> bool {
        self.uniforms.remove_uniform(name, &self.gl, renderer_running)
    }

    /// Add a sampler2D uniform and immediately generate its GL texture using
    /// the shader's own glow context.
    pub fn add_and_upload_sampler2d(
        &mut self,
        name: &str,
        sampler: Sampler2D,
    ) -> bool {
        let added = self.uniforms.add_uniform(
            name,
            UniformType::Sampler2D,
            &sampler as *const Sampler2D as *const std::os::raw::c_void,
        );
        if added {
            self.uniforms.set_all_sampler2d(&self.gl);
        }
        added
    }

    pub fn add_shader_toy_uniforms(&mut self) {
        let i_mouse = [0.0f32; 4];
        let i_resolution = [self.width as f32, self.height as f32, 0.0f32];
        let i_time = 0.0f32;

        self.uniforms.add_uniform("iMouse", UniformType::Vec4, &i_mouse as *const f32 as *const std::os::raw::c_void);
        self.uniforms.add_uniform("iResolution", UniformType::Vec3, &i_resolution as *const f32 as *const std::os::raw::c_void);
        self.uniforms.add_uniform("iTime", UniformType::Float, &i_time as *const f32 as *const std::os::raw::c_void);

        let black_data = vec![0u8; 4 * 4 * 4];
        for name in &["iChannel0", "iChannel1", "iChannel2", "iChannel3"] {
            let mut sampler = Sampler2D::new();
            sampler.add_rgba32(4, 4, &black_data);
            self.uniforms.add_uniform(name, UniformType::Sampler2D, &sampler as *const Sampler2D as *const std::os::raw::c_void);
        }
    }

    pub fn init_shader(&mut self) -> String {
        self.compile_error = String::new();

        if let Some(prog) = self.program.take() {
            unsafe { self.gl.delete_program(prog); }
        }

        self.program = self.create_program(&self.vertex_source.clone(), &self.fragment_source.clone());

        if let Some(prog) = self.program {
            self.uniforms.set_program(prog);
            #[cfg(not(target_arch = "wasm32"))]
            { self.start_instant = Some(std::time::Instant::now()); }
            #[cfg(target_arch = "wasm32")]
            { self.start_instant = Some(()); }

            // GL ES 3.0 requires a bound VAO.
            #[cfg(not(target_arch = "wasm32"))]
            {
                let vao = unsafe { self.gl.create_vertex_array().unwrap() };
                let vbo = unsafe { self.gl.create_buffer().unwrap() };

                unsafe {
                    self.gl.viewport(0, 0, self.width, self.height);
                    self.gl.clear_color(0.0, 0.0, 0.0, 1.0);

                    self.gl.bind_vertex_array(Some(vao));
                    self.gl.bind_buffer(glow::ARRAY_BUFFER, Some(vbo));

                    let vertex_bytes: &[u8] = std::slice::from_raw_parts(
                        QUAD_VERTICES.as_ptr() as *const u8,
                        std::mem::size_of_val(&QUAD_VERTICES),
                    );
                    self.gl.buffer_data_u8_slice(glow::ARRAY_BUFFER, vertex_bytes, glow::STATIC_DRAW);

                    self.gl.vertex_attrib_pointer_f32(0, 3, glow::FLOAT, false, 3 * std::mem::size_of::<f32>() as i32, 0);
                    self.gl.enable_vertex_attrib_array(0);

                    self.gl.bind_vertex_array(None);
                }

                self.vao = Some(vao);
                self.vbo = Some(vbo);

                if self.uses_fbo {
                    unsafe {
                        let native_tex = glow::NativeTexture(std::num::NonZeroU32::new(self.texture_name).unwrap());
                        self.gl.bind_texture(glow::TEXTURE_2D, Some(native_tex));
                        self.gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MIN_FILTER, glow::LINEAR as i32);
                        // Only allocate texture storage if the platform doesn't own
                        // it (e.g. iOS CVTextureCache provides pre-allocated storage).
                        if !self.platform_owns_texture {
                            self.gl.tex_image_2d(
                                glow::TEXTURE_2D,
                                0,
                                glow::RGBA as i32,
                                self.width,
                                self.height,
                                0,
                                glow::RGBA,
                                glow::UNSIGNED_BYTE,
                                glow::PixelUnpackData::Slice(None),
                            );
                        }

                        let fbo = self.gl.create_framebuffer().unwrap();
                        self.gl.bind_framebuffer(glow::DRAW_FRAMEBUFFER, Some(fbo));
                        self.gl.framebuffer_texture_2d(
                            glow::DRAW_FRAMEBUFFER,
                            glow::COLOR_ATTACHMENT0,
                            glow::TEXTURE_2D,
                            Some(glow::NativeTexture(std::num::NonZeroU32::new(self.texture_name).unwrap())),
                            0,
                        );

                        self.fbo = Some(fbo);
                    }
                }
            }

            self.uniforms.set_all_sampler2d(&self.gl);
        }

        self.compile_error.clone()
    }

    pub fn init_shader_toy(&mut self) -> String {
        if cfg!(any(target_os = "ios", target_os = "android", target_arch = "wasm32")) {
            self.vertex_source =
                "#version 300 es\n\
                 precision highp float;\n\
                 in vec4 a_Position;\n\
                 void main() {\n\
                     gl_Position = a_Position;\n\
                 }\n".to_string();
        } else {
            self.vertex_source =
                "#version 330 core\n\
                 in vec4 a_Position;\n\
                 void main() {\n\
                     gl_Position = a_Position;\n\
                 }\n".to_string();
        }

        let user_code = self.fragment_source.clone();

        if cfg!(any(target_os = "ios", target_os = "android", target_arch = "wasm32")) {
            let common =
                "#define HW_PERFORMANCE 0\n\
                 uniform sampler2D iChannel0;\n\
                 uniform sampler2D iChannel1;\n\
                 uniform sampler2D iChannel2;\n\
                 uniform sampler2D iChannel3;\n\
                 uniform vec4 iMouse;\n\
                 uniform vec3 iResolution;\n\
                 uniform float iTime;\n";

            // Android doesn't need Y-flip (Impeller preserves GL's Y-up from SurfaceTexture).
            let frag_coord = if cfg!(target_os = "android") {
                "gl_FragCoord.xy"
            } else {
                "vec2(gl_FragCoord.x, iResolution.y - gl_FragCoord.y)"
            };
            self.fragment_source = format!(
                "#version 300 es\n\
                 precision highp float;\n\
                 out vec4 fragColor;\n\
                 {common}\
                 {user_code}\n\
                 void main() {{\n\
                     mainImage(fragColor, {frag_coord});\n\
                 }}\n",
                common = common,
                user_code = user_code,
                frag_coord = frag_coord,
            );
        } else {
            let common =
                "#define HW_PERFORMANCE 1\n\
                 uniform sampler2D iChannel0;\n\
                 uniform sampler2D iChannel1;\n\
                 uniform sampler2D iChannel2;\n\
                 uniform sampler2D iChannel3;\n\
                 uniform vec4 iMouse;\n\
                 uniform vec3 iResolution;\n\
                 uniform float iTime;\n";

            self.fragment_source = format!(
                "#version 330 core\n\
                 #extension GL_OES_standard_derivatives : enable\n\
                 out vec4 fragColor;\n\
                 {common}\
                 {user_code}\n\
                 void main() {{\n\
                     mainImage(fragColor, vec2(gl_FragCoord.x, iResolution.y-gl_FragCoord.y));\n\
                 }}\n",
                common = common,
                user_code = user_code,
            );
        }

        self.add_shader_toy_uniforms();
        self.init_shader()
    }

    fn load_shader(&mut self, shader_type: u32, source: &str) -> Option<glow::Shader> {
        unsafe {
            let shader = self.gl.create_shader(shader_type).ok()?;
            self.gl.shader_source(shader, source);
            self.gl.compile_shader(shader);

            if !self.gl.get_shader_compile_status(shader) {
                let info_log = self.gl.get_shader_info_log(shader);
                let type_name = if shader_type == glow::VERTEX_SHADER {
                    "VERTEX"
                } else {
                    "FRAGMENT"
                };
                self.compile_error = format!("{} shader compile error:\n{}", type_name, info_log);
                self.gl.delete_shader(shader);
                return None;
            }

            Some(shader)
        }
    }

    fn create_program(&mut self, vertex_src: &str, fragment_src: &str) -> Option<glow::Program> {
        let vertex_shader = self.load_shader(glow::VERTEX_SHADER, vertex_src)?;
        let fragment_shader = self.load_shader(glow::FRAGMENT_SHADER, fragment_src)?;

        unsafe {
            let program = self.gl.create_program().ok()?;
            self.gl.attach_shader(program, vertex_shader);
            self.gl.attach_shader(program, fragment_shader);
            self.gl.link_program(program);

            let success = self.gl.get_program_link_status(program);
            if !success {
                let info_log = self.gl.get_program_info_log(program);
                self.compile_error = format!("Program link error:\n{}", info_log);
                self.gl.delete_program(program);
                self.gl.delete_shader(vertex_shader);
                self.gl.delete_shader(fragment_shader);
                return None;
            }

            self.gl.delete_shader(vertex_shader);
            self.gl.delete_shader(fragment_shader);

            Some(program)
        }
    }

    /// Draw a frame, making the GL context current first.
    #[cfg(not(target_arch = "wasm32"))]
    pub fn draw_frame(&mut self, platform: &PlatformContext) {
        platform.make_current();
        self.draw_frame_no_ctx(platform);
    }

    /// Draw a frame assuming the GL context is already current.
    /// The caller is responsible for calling `platform.make_current()` first.
    #[cfg(not(target_arch = "wasm32"))]
    pub fn draw_frame_no_ctx(&mut self, platform: &PlatformContext) {
        let program = match self.program {
            Some(p) => p,
            None => return,
        };

        let time = match self.start_instant {
            Some(instant) => instant.elapsed().as_secs_f32(),
            None => 0.0,
        };

        if self.uses_fbo {
            unsafe {
                self.gl.bind_framebuffer(glow::FRAMEBUFFER, self.fbo);
                self.gl.viewport(0, 0, self.width, self.height);
            }
        }

        unsafe {
            self.gl.clear(glow::COLOR_BUFFER_BIT);
            self.gl.use_program(Some(program));
        }

        self.uniforms.set_uniform_value("iTime", &time as *const f32 as *const std::os::raw::c_void);
        self.uniforms.send_all_uniforms(&self.gl);

        if self.uses_fbo {
            unsafe {
                self.gl.bind_framebuffer(glow::FRAMEBUFFER, self.fbo);

                self.gl.bind_vertex_array(self.vao);
                self.gl.draw_arrays(glow::TRIANGLES, 0, 6);
                self.gl.bind_vertex_array(None);

                if self.platform_owns_texture {
                    // Platform owns the texture (e.g. CVTextureCache).
                    // Flush to ensure GPU commands are submitted, then
                    // finish to block until the render is complete.
                    self.gl.flush();
                    self.gl.finish();
                } else {
                    // Read pixels back to CPU buffer.
                    // glReadPixels is synchronous: it waits for prior
                    // draw calls to complete, so no glFlush/glFinish needed.
                    self.gl.bind_framebuffer(glow::READ_FRAMEBUFFER, self.fbo);

                    let buf = platform.get_pixel_buffer();
                    if !buf.is_null() {
                        // If the pixel buffer has row padding (e.g. IOSurface),
                        // set GL_PACK_ROW_LENGTH so glReadPixels writes with
                        // the correct stride.
                        let row_pixels = if self.bytes_per_row > 0 {
                            self.bytes_per_row / 4
                        } else {
                            self.width
                        };
                        if row_pixels != self.width {
                            self.gl.pixel_store_i32(glow::PACK_ROW_LENGTH, row_pixels);
                        }

                        let buf_size = (row_pixels * self.height * 4) as usize;
                        let slice = std::slice::from_raw_parts_mut(buf, buf_size);

                        // iOS/Android support GL_BGRA_EXT for glReadPixels
                        // (GL_EXT_read_format_bgra).  Reading BGRA directly
                        // into the CVPixelBuffer avoids a CPU channel-swizzle.
                        let pixel_format = if cfg!(any(target_os = "ios", target_os = "android")) {
                            glow::BGRA
                        } else {
                            glow::RGBA
                        };
                        self.gl.read_pixels(
                            0,
                            0,
                            self.width,
                            self.height,
                            pixel_format,
                            glow::UNSIGNED_BYTE,
                            glow::PixelPackData::Slice(Some(slice)),
                        );

                        // Reset to default tight packing.
                        if row_pixels != self.width {
                            self.gl.pixel_store_i32(glow::PACK_ROW_LENGTH, 0);
                        }
                    }
                }
            }

            platform.clear_context();
            platform.mark_frame_available();
        } else {
            unsafe {
                self.gl.bind_framebuffer(glow::FRAMEBUFFER, None);
                self.gl.viewport(0, 0, self.width, self.height);
                self.gl.bind_vertex_array(self.vao);
                self.gl.draw_arrays(glow::TRIANGLES, 0, 6);
                self.gl.bind_vertex_array(None);
            }
            platform.swap_buffers();
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
impl Drop for Shader {
    fn drop(&mut self) {
        unsafe {
            if let Some(prog) = self.program.take() {
                self.gl.delete_program(prog);
            }
            if let Some(fbo) = self.fbo.take() {
                self.gl.delete_framebuffer(fbo);
            }
            if let Some(vao) = self.vao.take() {
                self.gl.delete_vertex_array(vao);
            }
            if let Some(vbo) = self.vbo.take() {
                self.gl.delete_buffer(vbo);
            }
        }
    }
}
