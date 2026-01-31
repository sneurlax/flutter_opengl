use glow::HasContext;

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
    program: Option<glow::NativeProgram>,
    vao: Option<glow::NativeVertexArray>,
    vbo: Option<glow::NativeBuffer>,
    fbo: Option<glow::NativeFramebuffer>,
    width: i32,
    height: i32,
    start_instant: Option<std::time::Instant>,
    is_continuous: bool,
    uniforms: UniformQueue,
    vertex_source: String,
    fragment_source: String,
    compile_error: String,
    texture_name: u32,
    uses_fbo: bool,
}

impl Shader {
    pub fn new(gl: glow::Context, width: i32, height: i32, texture_name: u32, uses_fbo: bool) -> Self {
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

    pub fn program(&self) -> Option<glow::NativeProgram> {
        self.program
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
            self.start_instant = Some(std::time::Instant::now());

            if self.uses_fbo {
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

                    self.gl.bind_texture(glow::TEXTURE_2D, Some(glow::NativeTexture(std::num::NonZeroU32::new(self.texture_name).unwrap())));
                    self.gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MIN_FILTER, glow::LINEAR as i32);
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

                self.vao = Some(vao);
                self.vbo = Some(vbo);
            }

            self.uniforms.set_all_sampler2d(&self.gl);
        }

        self.compile_error.clone()
    }

    pub fn init_shader_toy(&mut self) -> String {
        #[cfg(not(target_arch = "wasm32"))]
        {
            self.vertex_source =
                "#version 330 core\n\
                 in vec4 a_Position;\n\
                 void main() {\n\
                     gl_Position = a_Position;\n\
                 }\n".to_string();
        }

        #[cfg(target_arch = "wasm32")]
        {
            self.vertex_source =
                "#version 300 es\n\
                 precision highp float;\n\
                 in vec4 a_Position;\n\
                 void main() {\n\
                     gl_Position = a_Position;\n\
                 }\n".to_string();
        }

        let common =
            "#define HW_PERFORMANCE 1\n\
             uniform sampler2D iChannel0;\n\
             uniform sampler2D iChannel1;\n\
             uniform sampler2D iChannel2;\n\
             uniform sampler2D iChannel3;\n\
             uniform vec4 iMouse;\n\
             uniform vec3 iResolution;\n\
             uniform float iTime;\n";

        #[cfg(target_arch = "wasm32")]
        let common = {
            let _ = common;
            "#define HW_PERFORMANCE 0\n\
             uniform sampler2D iChannel0;\n\
             uniform sampler2D iChannel1;\n\
             uniform sampler2D iChannel2;\n\
             uniform sampler2D iChannel3;\n\
             uniform vec4 iMouse;\n\
             uniform vec3 iResolution;\n\
             uniform float iTime;\n"
        };

        let user_code = self.fragment_source.clone();

        #[cfg(not(target_arch = "wasm32"))]
        {
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

        #[cfg(target_arch = "wasm32")]
        {
            self.fragment_source = format!(
                "#version 300 es\n\
                 precision highp float;\n\
                 out vec4 fragColor;\n\
                 {common}\
                 {user_code}\n\
                 void main() {{\n\
                     mainImage(fragColor, gl_FragCoord.xy);\n\
                 }}\n",
                common = common,
                user_code = user_code,
            );
        }

        self.add_shader_toy_uniforms();
        self.init_shader()
    }

    fn load_shader(&mut self, shader_type: u32, source: &str) -> Option<glow::NativeShader> {
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

    fn create_program(&mut self, vertex_src: &str, fragment_src: &str) -> Option<glow::NativeProgram> {
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

    pub fn draw_frame(&mut self, platform: &PlatformContext) {
        let program = match self.program {
            Some(p) => p,
            None => return,
        };

        platform.make_current();

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

                self.gl.bind_framebuffer(glow::READ_FRAMEBUFFER, self.fbo);

                let buf = platform.get_pixel_buffer();
                if !buf.is_null() {
                    self.gl.read_pixels(
                        0,
                        0,
                        self.width,
                        self.height,
                        glow::RGBA,
                        glow::UNSIGNED_BYTE,
                        glow::PixelPackData::Slice(
                            Some(std::slice::from_raw_parts_mut(buf, (self.width * self.height * 4) as usize)),
                        ),
                    );
                }

                self.gl.flush();
                self.gl.finish();
            }

            platform.clear_context();
            platform.mark_frame_available();
        } else {
            unsafe {
                self.gl.draw_arrays(glow::TRIANGLES, 0, 6);
            }
            platform.swap_buffers();
        }
    }
}
