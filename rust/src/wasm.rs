use wasm_bindgen::prelude::*;
use web_sys::{HtmlCanvasElement, WebGl2RenderingContext};
use glow::HasContext;

use crate::sampler::Sampler2D;
use crate::shader::Shader;
use crate::uniform::UniformType;

const QUAD_VERTICES: [f32; 18] = [
    -1.0, -1.0, 0.0,
    -1.0,  1.0, 0.0,
     1.0, -1.0, 0.0,
    -1.0,  1.0, 0.0,
     1.0,  1.0, 0.0,
     1.0, -1.0, 0.0,
];

/// Obtain `performance.now()` from the browser (milliseconds).
fn performance_now() -> f64 {
    web_sys::window()
        .expect("no global window")
        .performance()
        .expect("no performance object")
        .now()
}

/// WebGL2/WASM renderer. Single-threaded; JS drives the loop via
/// `requestAnimationFrame` → `render_frame()`.
#[wasm_bindgen]
pub struct WasmRenderer {
    webgl2_ctx: WebGl2RenderingContext,
    shader: Option<Shader>,
    vao: Option<glow::VertexArray>,
    vbo: Option<glow::Buffer>,
    canvas: HtmlCanvasElement,
    width: i32,
    height: i32,
    running: bool,
    start_time: f64,
    mouse: [f32; 4],
    fps: f64,
    last_fps_time: f64,
    fps_frame_count: u32,
    is_shader_toy: bool,
    animation_frame_id: i32,
}

#[wasm_bindgen]
impl WasmRenderer {
    // -- Construction --

    #[wasm_bindgen(constructor)]
    pub fn new(canvas: HtmlCanvasElement, width: u32, height: u32) -> Result<WasmRenderer, JsValue> {

        let webgl2_ctx: WebGl2RenderingContext = canvas
            .get_context("webgl2")?
            .ok_or_else(|| JsValue::from_str("failed to get WebGL2 context"))?
            .dyn_into::<WebGl2RenderingContext>()
            .map_err(|_| JsValue::from_str("context is not WebGl2RenderingContext"))?;

        let now = performance_now();

        Ok(WasmRenderer {
            webgl2_ctx,
            shader: None,
            vao: None,
            vbo: None,
            canvas,
            width: width as i32,
            height: height as i32,
            running: false,
            start_time: now,
            mouse: [0.0; 4],
            fps: 0.0,
            last_fps_time: now,
            fps_frame_count: 0,
            is_shader_toy: false,
            animation_frame_id: 0,
        })
    }

    // -- glow context --

    fn create_glow_context(&self) -> glow::Context {
        glow::Context::from_webgl2_context(self.webgl2_ctx.clone())
    }

    fn setup_quad_geometry(&mut self) {
        let s = match self.shader.as_ref() {
            Some(s) => s,
            None => return,
        };

        let gl = s.gl();

        // Discard old VAO/VBO handles — they belong to the previous shader's
        // glow context (slotmap) which was already dropped, so the keys are
        // invalid in the new context. The underlying WebGL resources will be
        // garbage-collected by the browser.
        self.vao = None;
        self.vbo = None;

        unsafe {
            let vao = gl.create_vertex_array().unwrap();
            let vbo = gl.create_buffer().unwrap();

            gl.viewport(0, 0, self.width, self.height);
            gl.clear_color(0.0, 0.0, 0.0, 1.0);

            gl.bind_vertex_array(Some(vao));
            gl.bind_buffer(glow::ARRAY_BUFFER, Some(vbo));

            let vertex_bytes: &[u8] = std::slice::from_raw_parts(
                QUAD_VERTICES.as_ptr() as *const u8,
                std::mem::size_of_val(&QUAD_VERTICES),
            );
            gl.buffer_data_u8_slice(glow::ARRAY_BUFFER, vertex_bytes, glow::STATIC_DRAW);

            gl.vertex_attrib_pointer_f32(
                0,
                3,
                glow::FLOAT,
                false,
                3 * std::mem::size_of::<f32>() as i32,
                0,
            );
            gl.enable_vertex_attrib_array(0);

            gl.bind_vertex_array(None);

            self.vao = Some(vao);
            self.vbo = Some(vbo);
        }
    }

    // -- Getters --

    #[wasm_bindgen]
    pub fn renderer_status(&self) -> bool {
        self.running
    }

    #[wasm_bindgen]
    pub fn get_texture_width(&self) -> i32 {
        self.width
    }

    #[wasm_bindgen]
    pub fn get_texture_height(&self) -> i32 {
        self.height
    }

    #[wasm_bindgen]
    pub fn get_fps(&self) -> f64 {
        self.fps
    }

    #[wasm_bindgen]
    pub fn get_vertex_shader(&self) -> String {
        match &self.shader {
            Some(s) => s.vertex_source().to_string(),
            None => String::new(),
        }
    }

    #[wasm_bindgen]
    pub fn get_fragment_shader(&self) -> String {
        match &self.shader {
            Some(s) => s.fragment_source().to_string(),
            None => String::new(),
        }
    }

    // -- Render loop control --

    /// Mark the renderer as running. The JS side should start calling
    /// `render_frame()` via `requestAnimationFrame` after this.
    #[wasm_bindgen]
    pub fn start(&mut self) {
        self.running = true;
        self.start_time = performance_now();
        self.last_fps_time = self.start_time;
        self.fps_frame_count = 0;
    }

    /// Mark the renderer as stopped. The JS side should stop its
    /// `requestAnimationFrame` loop.
    #[wasm_bindgen]
    pub fn stop(&mut self) {
        self.running = false;
        self.animation_frame_id = 0;
    }

    // -- Shader compilation --

    /// Compile and link a custom vertex + fragment shader pair.
    /// Returns an empty string on success, or the compile/link error.
    #[wasm_bindgen]
    pub fn set_shader(
        &mut self,
        is_continuous: bool,
        vertex_src: &str,
        fragment_src: &str,
    ) -> String {
        self.is_shader_toy = false;

        // Drop old shader to release GL resources.
        self.shader = None;

        let gl = self.create_glow_context();
        let mut s = Shader::new(gl, self.width, self.height, 0, false);
        s.set_shaders_text(vertex_src.to_string(), fragment_src.to_string());
        s.set_shaders_size(self.width, self.height);
        s.set_is_continuous(is_continuous);

        let error = s.init_shader();
        let is_valid = s.is_valid();
        self.shader = Some(s);

        if is_valid {
            self.setup_quad_geometry();
        }

        error
    }

    /// Compile a ShaderToy-style fragment shader (vertex shader is generated
    /// automatically, standard ShaderToy uniforms are added).
    /// Returns an empty string on success, or the compile/link error.
    #[wasm_bindgen]
    pub fn set_shader_toy(&mut self, fragment_src: &str) -> String {
        self.is_shader_toy = true;

        // Drop old shader.
        self.shader = None;

        let gl = self.create_glow_context();
        let mut s = Shader::new(gl, self.width, self.height, 0, false);
        s.set_shaders_text(String::new(), fragment_src.to_string());
        s.set_shaders_size(self.width, self.height);
        s.set_is_continuous(true);

        let error = s.init_shader_toy();
        let is_valid = s.is_valid();
        self.start_time = performance_now();
        self.shader = Some(s);

        if is_valid {
            self.setup_quad_geometry();
        }

        error
    }

    // -- ShaderToy --

    #[wasm_bindgen]
    pub fn add_shader_toy_uniforms(&mut self) {
        if let Some(ref mut s) = self.shader {
            s.add_shader_toy_uniforms();
        }
    }

    #[wasm_bindgen]
    pub fn set_mouse_position(&mut self, x: f32, y: f32, z: f32, w: f32) {
        self.mouse = [x, y, z, w];
        if let Some(ref mut s) = self.shader {
            s.uniforms_mut().set_uniform_value(
                "iMouse",
                self.mouse.as_ptr() as *const std::os::raw::c_void,
            );
        }
    }

    // -- Add uniforms --

    #[wasm_bindgen]
    pub fn add_bool_uniform(&mut self, name: &str, val: bool) -> bool {
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().add_uniform(
                name,
                UniformType::Bool,
                &val as *const bool as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn add_int_uniform(&mut self, name: &str, val: i32) -> bool {
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().add_uniform(
                name,
                UniformType::Int,
                &val as *const i32 as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn add_float_uniform(&mut self, name: &str, val: f32) -> bool {
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().add_uniform(
                name,
                UniformType::Float,
                &val as *const f32 as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn add_vec2_uniform(&mut self, name: &str, x: f32, y: f32) -> bool {
        let v = [x, y];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().add_uniform(
                name,
                UniformType::Vec2,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn add_vec3_uniform(&mut self, name: &str, x: f32, y: f32, z: f32) -> bool {
        let v = [x, y, z];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().add_uniform(
                name,
                UniformType::Vec3,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn add_vec4_uniform(&mut self, name: &str, x: f32, y: f32, z: f32, w: f32) -> bool {
        let v = [x, y, z, w];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().add_uniform(
                name,
                UniformType::Vec4,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn add_mat2_uniform(&mut self, name: &str, v0: f32, v1: f32, v2: f32, v3: f32) -> bool {
        let v = [v0, v1, v2, v3];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().add_uniform(
                name,
                UniformType::Mat2,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn add_mat3_uniform(
        &mut self,
        name: &str,
        v0: f32, v1: f32, v2: f32,
        v3: f32, v4: f32, v5: f32,
        v6: f32, v7: f32, v8: f32,
    ) -> bool {
        let v = [v0, v1, v2, v3, v4, v5, v6, v7, v8];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().add_uniform(
                name,
                UniformType::Mat3,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn add_mat4_uniform(
        &mut self,
        name: &str,
        v0: f32, v1: f32, v2: f32, v3: f32,
        v4: f32, v5: f32, v6: f32, v7: f32,
        v8: f32, v9: f32, v10: f32, v11: f32,
        v12: f32, v13: f32, v14: f32, v15: f32,
    ) -> bool {
        let v = [v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().add_uniform(
                name,
                UniformType::Mat4,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    // -- Set uniforms --

    #[wasm_bindgen]
    pub fn set_bool_uniform(&mut self, name: &str, val: bool) -> bool {
        // UniformQueue::set_uniform_value reads a f32 for non-Sampler types.
        let fval: f32 = if val { 1.0 } else { 0.0 };
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().set_uniform_value(
                name,
                &fval as *const f32 as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn set_int_uniform(&mut self, name: &str, val: i32) -> bool {
        let fval = val as f32;
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().set_uniform_value(
                name,
                &fval as *const f32 as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn set_float_uniform(&mut self, name: &str, val: f32) -> bool {
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().set_uniform_value(
                name,
                &val as *const f32 as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn set_vec2_uniform(&mut self, name: &str, x: f32, y: f32) -> bool {
        let v = [x, y];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().set_uniform_value(
                name,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn set_vec3_uniform(&mut self, name: &str, x: f32, y: f32, z: f32) -> bool {
        let v = [x, y, z];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().set_uniform_value(
                name,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn set_vec4_uniform(&mut self, name: &str, x: f32, y: f32, z: f32, w: f32) -> bool {
        let v = [x, y, z, w];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().set_uniform_value(
                name,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn set_mat2_uniform(&mut self, name: &str, v0: f32, v1: f32, v2: f32, v3: f32) -> bool {
        let v = [v0, v1, v2, v3];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().set_uniform_value(
                name,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn set_mat3_uniform(
        &mut self,
        name: &str,
        v0: f32, v1: f32, v2: f32,
        v3: f32, v4: f32, v5: f32,
        v6: f32, v7: f32, v8: f32,
    ) -> bool {
        let v = [v0, v1, v2, v3, v4, v5, v6, v7, v8];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().set_uniform_value(
                name,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    #[wasm_bindgen]
    pub fn set_mat4_uniform(
        &mut self,
        name: &str,
        v0: f32, v1: f32, v2: f32, v3: f32,
        v4: f32, v5: f32, v6: f32, v7: f32,
        v8: f32, v9: f32, v10: f32, v11: f32,
        v12: f32, v13: f32, v14: f32, v15: f32,
    ) -> bool {
        let v = [v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15];
        match self.shader.as_mut() {
            Some(s) => s.uniforms_mut().set_uniform_value(
                name,
                v.as_ptr() as *const std::os::raw::c_void,
            ),
            None => false,
        }
    }

    // -- Remove uniforms --

    #[wasm_bindgen]
    pub fn remove_uniform(&mut self, name: &str) -> bool {
        let running = self.running;
        match self.shader.as_mut() {
            Some(s) => s.remove_uniform(name, running),
            None => false,
        }
    }

    // -- Sampler2D --

    #[wasm_bindgen]
    pub fn add_sampler2d_uniform(
        &mut self,
        name: &str,
        width: i32,
        height: i32,
        data: &[u8],
    ) -> bool {
        let s = match self.shader.as_mut() {
            Some(s) => s,
            None => return false,
        };

        let mut sampler = Sampler2D::new();
        sampler.add_rgba32(width, height, data);
        s.add_and_upload_sampler2d(name, sampler)
    }

    #[wasm_bindgen]
    pub fn replace_sampler2d_uniform(
        &mut self,
        name: &str,
        width: i32,
        height: i32,
        data: &[u8],
    ) -> bool {
        match self.shader.as_mut() {
            Some(s) => s.replace_and_upload_sampler2d(name, width, height, data),
            None => false,
        }
    }

    // -- Frame rendering --

    /// Render a single frame. This is intended to be called from the JS
    /// `requestAnimationFrame` callback.
    ///
    /// On WASM we render directly to the canvas backbuffer (no FBO, no
    /// `glReadPixels`). WebGL auto-presents at the end of the event-loop
    /// turn.
    #[wasm_bindgen]
    pub fn render_frame(&mut self) {
        if !self.running {
            return;
        }

        let vao = match self.vao {
            Some(vao) => vao,
            None => return,
        };

        let s = match self.shader.as_mut() {
            Some(s) if s.is_valid() => s,
            _ => return,
        };

        // Elapsed time since start (seconds), used for iTime.
        let now = performance_now();
        let elapsed_secs = ((now - self.start_time) / 1000.0) as f32;

        let gl = s.gl();

        unsafe {
            gl.viewport(0, 0, self.width, self.height);
            gl.clear_color(0.0, 0.0, 0.0, 1.0);
            gl.clear(glow::COLOR_BUFFER_BIT);
            gl.use_program(s.program());
        }

        // Update iTime if present.
        s.uniforms_mut().set_uniform_value(
            "iTime",
            &elapsed_secs as *const f32 as *const std::os::raw::c_void,
        );

        // Update iMouse if present.
        s.uniforms_mut().set_uniform_value(
            "iMouse",
            self.mouse.as_ptr() as *const std::os::raw::c_void,
        );

        s.uniforms().send_all_uniforms(s.gl());

        unsafe {
            s.gl().bind_vertex_array(Some(vao));
            s.gl().draw_arrays(glow::TRIANGLES, 0, 6);
            s.gl().bind_vertex_array(None);
            s.gl().flush();
        }

        // FPS tracking.
        self.fps_frame_count += 1;
        let fps_elapsed = (now - self.last_fps_time) / 1000.0;
        if fps_elapsed >= 1.0 {
            let current_fps = self.fps_frame_count as f64 / fps_elapsed;
            self.fps = current_fps * 0.5 + self.fps * 0.5;
            self.fps_frame_count = 0;
            self.last_fps_time = now;
        }
    }
}
