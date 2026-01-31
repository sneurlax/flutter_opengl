use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::time::Instant;

use glow::HasContext;

use crate::platform::PlatformContext;
use crate::shader::Shader;

// ---------------------------------------------------------------------------
// Messages sent from the FFI / API thread to the render thread
// ---------------------------------------------------------------------------

pub(crate) enum Message {
    StopRenderer,
    NewShader,
    NewTexture,
    DeleteTexture(u32),
    SetTexture {
        n_texture: i32,
        texture_index: u32,
        width: i32,
        height: i32,
        data: Vec<u8>,
    },
}

// ---------------------------------------------------------------------------
// Pending uniform operations queued from the FFI thread
// ---------------------------------------------------------------------------

use crate::sampler::Sampler2D;
use crate::uniform::UniformType;

enum UniformOp {
    Add {
        name: String,
        uniform_type: UniformType,
        data: Vec<u8>,
    },
    SetValue {
        name: String,
        data: Vec<u8>,
    },
    Remove {
        name: String,
    },
    AddShaderToyUniforms,
    SetMousePosition {
        x: f32,
        y: f32,
        z: f32,
        w: f32,
    },
    AddSampler2D {
        name: String,
        sampler: Sampler2D,
    },
    ReplaceSampler2D {
        name: String,
        width: i32,
        height: i32,
        data: Vec<u8>,
    },
    NewTexture,
}

// ---------------------------------------------------------------------------
// Shared state between the API thread and the render thread
// ---------------------------------------------------------------------------

pub struct SharedState {
    pub(crate) messages: Mutex<Vec<Message>>,
    pub(crate) loop_running: AtomicBool,
    pub(crate) shader_compiled: AtomicBool,
    pub(crate) frame_rate: Mutex<f64>,
    pub(crate) compile_error: Mutex<String>,

    // Shader source written by FFI thread, read by render thread on NewShader
    pub(crate) new_vertex_source: Mutex<String>,
    pub(crate) new_fragment_source: Mutex<String>,
    pub(crate) new_is_continuous: AtomicBool,
    pub(crate) is_shader_toy: AtomicBool,

    // Current shader source (updated after compilation for getters)
    pub(crate) current_vertex_source: Mutex<String>,
    pub(crate) current_fragment_source: Mutex<String>,

    // Shader metadata mirrored for cross-thread queries
    pub(crate) shader_valid: AtomicBool,
    pub(crate) shader_continuous: AtomicBool,
    pub(crate) shader_width: Mutex<i32>,
    pub(crate) shader_height: Mutex<i32>,

    // Pending uniform operations from the FFI thread
    pending_uniform_ops: Mutex<Vec<UniformOp>>,

    // Surface / texture geometry (immutable after construction)
    pub(crate) width: i32,
    pub(crate) height: i32,
    pub(crate) texture_name: u32,
    pub(crate) uses_fbo: bool,

    // The PlatformContext is moved to the render thread on start
    pub(crate) platform: Mutex<Option<PlatformContext>>,
}

// ---------------------------------------------------------------------------
// Renderer -- public API (called from FFI / API thread)
// ---------------------------------------------------------------------------

pub struct Renderer {
    shared: Arc<SharedState>,
}

impl Renderer {
    pub fn new(platform: PlatformContext) -> Self {
        let w = platform.width;
        let h = platform.height;
        let tn = platform.texture_name;
        let fbo = platform.uses_fbo;

        Renderer {
            shared: Arc::new(SharedState {
                messages: Mutex::new(Vec::new()),
                loop_running: AtomicBool::new(false),
                shader_compiled: AtomicBool::new(true),
                frame_rate: Mutex::new(0.0),
                compile_error: Mutex::new(String::new()),
                new_vertex_source: Mutex::new(String::new()),
                new_fragment_source: Mutex::new(String::new()),
                new_is_continuous: AtomicBool::new(true),
                is_shader_toy: AtomicBool::new(false),
                current_vertex_source: Mutex::new(String::new()),
                current_fragment_source: Mutex::new(String::new()),
                shader_valid: AtomicBool::new(false),
                shader_continuous: AtomicBool::new(false),
                shader_width: Mutex::new(w),
                shader_height: Mutex::new(h),
                pending_uniform_ops: Mutex::new(Vec::new()),
                width: w,
                height: h,
                texture_name: tn,
                uses_fbo: fbo,
                platform: Mutex::new(Some(platform)),
            }),
        }
    }

    // -- Thread control -----------------------------------------------------

    /// Spawn the render-loop thread. No-op if already running.
    pub fn start_thread(&self) {
        if self.shared.loop_running.load(Ordering::SeqCst) {
            return;
        }
        let shared = self.shared.clone();
        std::thread::spawn(move || {
            render_loop(shared);
        });
    }

    /// Ask the render thread to stop (non-blocking).
    pub fn stop(&self) {
        self.shared
            .messages
            .lock()
            .unwrap()
            .push(Message::StopRenderer);
    }

    pub fn is_looping(&self) -> bool {
        self.shared.loop_running.load(Ordering::SeqCst)
    }

    // -- Shader compilation -------------------------------------------------

    /// Compile a new shader. Blocks until compilation finishes on the render
    /// thread and returns the compile-error string (empty on success).
    pub fn set_shader(
        &self,
        is_continuous: bool,
        vertex: &str,
        fragment: &str,
    ) -> String {
        *self.shared.compile_error.lock().unwrap() = String::new();
        self.shared.is_shader_toy.store(false, Ordering::SeqCst);
        *self.shared.new_vertex_source.lock().unwrap() = vertex.to_string();
        *self.shared.new_fragment_source.lock().unwrap() = fragment.to_string();
        self.shared
            .new_is_continuous
            .store(is_continuous, Ordering::SeqCst);
        self.shared.shader_compiled.store(false, Ordering::SeqCst);
        self.shared
            .messages
            .lock()
            .unwrap()
            .push(Message::NewShader);

        // Spin-wait for the render thread to finish compilation.
        while !self.shared.shader_compiled.load(Ordering::SeqCst) {
            std::thread::yield_now();
        }

        self.shared.compile_error.lock().unwrap().clone()
    }

    /// Compile a ShaderToy shader. Blocks until compilation finishes.
    pub fn set_shader_toy(&self, fragment: &str) -> String {
        *self.shared.compile_error.lock().unwrap() = String::new();
        self.shared.is_shader_toy.store(true, Ordering::SeqCst);
        *self.shared.new_vertex_source.lock().unwrap() = String::new();
        *self.shared.new_fragment_source.lock().unwrap() = fragment.to_string();
        self.shared.new_is_continuous.store(true, Ordering::SeqCst);
        self.shared.shader_compiled.store(false, Ordering::SeqCst);
        self.shared
            .messages
            .lock()
            .unwrap()
            .push(Message::NewShader);

        while !self.shared.shader_compiled.load(Ordering::SeqCst) {
            std::thread::yield_now();
        }

        self.shared.compile_error.lock().unwrap().clone()
    }

    // -- Texture messages ---------------------------------------------------

    /// Tell the render thread to assign GL textures to all Sampler2D uniforms.
    pub fn set_new_texture_msg(&self) {
        self.shared
            .messages
            .lock()
            .unwrap()
            .push(Message::NewTexture);
    }

    /// Tell the render thread to delete a GL texture by raw id.
    pub fn delete_texture_msg(&self, texture_id: u32) {
        self.shared
            .messages
            .lock()
            .unwrap()
            .push(Message::DeleteTexture(texture_id));
    }

    /// Tell the render thread to upload new pixel data into an existing texture.
    pub fn set_texture_msg(
        &self,
        n_texture: i32,
        texture_index: u32,
        width: i32,
        height: i32,
        data: Vec<u8>,
    ) {
        self.shared
            .messages
            .lock()
            .unwrap()
            .push(Message::SetTexture {
                n_texture,
                texture_index,
                width,
                height,
                data,
            });
    }

    // -- Uniform operations (queued, applied on render thread) ---------------

    /// Queue an `addUniform` to be executed on the render thread.
    /// `data` is the raw bytes of the uniform value (copied from the FFI pointer).
    pub fn add_uniform(
        &self,
        name: &str,
        uniform_type: UniformType,
        data: Vec<u8>,
    ) {
        self.shared
            .pending_uniform_ops
            .lock()
            .unwrap()
            .push(UniformOp::Add {
                name: name.to_string(),
                uniform_type,
                data,
            });
    }

    /// Queue a `setUniformValue` to be executed on the render thread.
    pub fn set_uniform_value(&self, name: &str, data: Vec<u8>) {
        self.shared
            .pending_uniform_ops
            .lock()
            .unwrap()
            .push(UniformOp::SetValue {
                name: name.to_string(),
                data,
            });
    }

    /// Queue a `removeUniform` to be executed on the render thread.
    pub fn remove_uniform(&self, name: &str) {
        self.shared
            .pending_uniform_ops
            .lock()
            .unwrap()
            .push(UniformOp::Remove {
                name: name.to_string(),
            });
    }

    /// Queue adding the standard ShaderToy uniforms.
    pub fn add_shader_toy_uniforms(&self) {
        self.shared
            .pending_uniform_ops
            .lock()
            .unwrap()
            .push(UniformOp::AddShaderToyUniforms);
    }

    /// Queue a mouse-position update (ShaderToy `iMouse` uniform).
    pub fn set_mouse_position(&self, x: f32, y: f32, z: f32, w: f32) {
        self.shared
            .pending_uniform_ops
            .lock()
            .unwrap()
            .push(UniformOp::SetMousePosition { x, y, z, w });
    }

    // -- Shared handle -------------------------------------------------------

    pub fn has_shader(&self) -> bool {
        self.shared.shader_valid.load(Ordering::SeqCst)
    }

    pub fn shared_handle(&self) -> Arc<SharedState> {
        self.shared.clone()
    }

    // -- Static blocking shader compilation ----------------------------------

    pub fn set_shader_blocking(shared: &SharedState, is_continuous: bool, vertex: &str, fragment: &str) -> String {
        *shared.compile_error.lock().unwrap() = String::new();
        shared.is_shader_toy.store(false, Ordering::SeqCst);
        *shared.new_vertex_source.lock().unwrap() = vertex.to_string();
        *shared.new_fragment_source.lock().unwrap() = fragment.to_string();
        shared.new_is_continuous.store(is_continuous, Ordering::SeqCst);
        shared.shader_compiled.store(false, Ordering::SeqCst);
        shared.messages.lock().unwrap().push(Message::NewShader);
        while !shared.shader_compiled.load(Ordering::SeqCst) {
            std::thread::yield_now();
        }
        shared.compile_error.lock().unwrap().clone()
    }

    pub fn set_shader_toy_blocking(shared: &SharedState, fragment: &str) -> String {
        *shared.compile_error.lock().unwrap() = String::new();
        shared.is_shader_toy.store(true, Ordering::SeqCst);
        *shared.new_vertex_source.lock().unwrap() = String::new();
        *shared.new_fragment_source.lock().unwrap() = fragment.to_string();
        shared.new_is_continuous.store(true, Ordering::SeqCst);
        shared.shader_compiled.store(false, Ordering::SeqCst);
        shared.messages.lock().unwrap().push(Message::NewShader);
        while !shared.shader_compiled.load(Ordering::SeqCst) {
            std::thread::yield_now();
        }
        shared.compile_error.lock().unwrap().clone()
    }

    // -- Sampler2D uniform operations ----------------------------------------

    pub fn add_sampler2d_uniform(&self, name: &str, sampler: Sampler2D) {
        self.shared
            .pending_uniform_ops
            .lock()
            .unwrap()
            .push(UniformOp::AddSampler2D {
                name: name.to_string(),
                sampler,
            });
    }

    pub fn replace_sampler2d_uniform(&self, name: &str, w: i32, h: i32, data: Vec<u8>) {
        self.shared
            .pending_uniform_ops
            .lock()
            .unwrap()
            .push(UniformOp::ReplaceSampler2D {
                name: name.to_string(),
                width: w,
                height: h,
                data,
            });
    }

    pub fn queue_new_texture(&self) {
        self.shared
            .pending_uniform_ops
            .lock()
            .unwrap()
            .push(UniformOp::NewTexture);
    }

    // -- Getters (thread-safe reads of mirrored state) ----------------------

    pub fn get_frame_rate(&self) -> f64 {
        *self.shared.frame_rate.lock().unwrap()
    }

    pub fn get_vertex_source(&self) -> String {
        self.shared.current_vertex_source.lock().unwrap().clone()
    }

    pub fn get_fragment_source(&self) -> String {
        self.shared.current_fragment_source.lock().unwrap().clone()
    }

    pub fn is_shader_valid(&self) -> bool {
        self.shared.shader_valid.load(Ordering::SeqCst)
    }

    pub fn is_shader_continuous(&self) -> bool {
        self.shared.shader_continuous.load(Ordering::SeqCst)
    }

    pub fn get_shader_width(&self) -> i32 {
        *self.shared.shader_width.lock().unwrap()
    }

    pub fn get_shader_height(&self) -> i32 {
        *self.shared.shader_height.lock().unwrap()
    }
}

// ---------------------------------------------------------------------------
// Apply pending uniform operations to the Shader on the render thread
// ---------------------------------------------------------------------------

fn apply_uniform_ops(shader: &mut Shader, ops: &mut Vec<UniformOp>, loop_gl: &glow::Context) {
    for op in ops.drain(..) {
        match op {
            UniformOp::Add {
                name,
                uniform_type,
                data,
            } => {
                shader.uniforms_mut().add_uniform(
                    &name,
                    uniform_type,
                    data.as_ptr() as *const std::os::raw::c_void,
                );
            }
            UniformOp::SetValue { name, data } => {
                shader.uniforms_mut().set_uniform_value(
                    &name,
                    data.as_ptr() as *const std::os::raw::c_void,
                );
            }
            UniformOp::Remove { name } => {
                // Skip GL texture deletion while the render loop is active.
                shader.uniforms_mut().remove_uniform(&name, &loop_gl, true);
            }
            UniformOp::AddShaderToyUniforms => {
                shader.add_shader_toy_uniforms();
            }
            UniformOp::SetMousePosition { x, y, z, w } => {
                let mouse = [x, y, z, w];
                shader.uniforms_mut().set_uniform_value(
                    "iMouse",
                    mouse.as_ptr() as *const std::os::raw::c_void,
                );
            }
            UniformOp::AddSampler2D { name, sampler } => {
                shader.uniforms_mut().add_uniform(
                    &name,
                    UniformType::Sampler2D,
                    &sampler as *const Sampler2D as *const std::os::raw::c_void,
                );
            }
            UniformOp::ReplaceSampler2D { name, width, height, data } => {
                shader.uniforms_mut().replace_sampler2d(&name, width, height, &data);
                // Re-upload the texture to GPU — replace_texture only updates
                // CPU data, and set_all_sampler2d skips already-assigned samplers.
                if let Some(sampler) = shader.uniforms_mut().get_sampler2d(&name) {
                    let n = sampler.n_texture;
                    if n != -1 {
                        sampler.gen_texture(loop_gl, n);
                    }
                }
            }
            UniformOp::NewTexture => {
                shader.uniforms_mut().set_all_sampler2d(loop_gl);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Helper: create a glow::Context from the platform's GL loader
// ---------------------------------------------------------------------------

/// # Safety
/// The GL context must be current on the calling thread.
unsafe fn create_gl_context(platform: &PlatformContext) -> glow::Context {
    match platform.load_gl_proc {
        Some(loader) => glow::Context::from_loader_function(|name| {
            let cname = std::ffi::CString::new(name).unwrap();
            loader(cname.as_ptr()) as *const _
        }),
        None => panic!("No GL loader function provided in PlatformContext"),
    }
}

// ---------------------------------------------------------------------------
// Render loop (runs on a dedicated thread)
// ---------------------------------------------------------------------------

fn render_loop(shared: Arc<SharedState>) {
    shared.loop_running.store(true, Ordering::SeqCst);

    // Take the PlatformContext out of shared state -- it will live on this
    // thread for the duration of the loop.
    let platform = shared
        .platform
        .lock()
        .unwrap()
        .take()
        .expect("PlatformContext missing when starting render loop");

    // Create a lightweight glow::Context that the render loop keeps for GL
    // calls that happen outside of a Shader (e.g. DeleteTexture, SetTexture).
    // Each Shader also gets its own glow::Context via `create_gl_context`.
    platform.make_current();
    let loop_gl = unsafe { create_gl_context(&platform) };
    platform.clear_context();

    // -- Frame-rate tracking ------------------------------------------------
    let mut shader: Option<Shader> = None;
    let mut frames: u32 = 0;
    let mut frame_rate: f64 = 0.0;
    let mut start_fps = Instant::now();
    let mut end_fps = Instant::now();
    let mut start_draw = Instant::now();
    let mut end_draw;
    // Cap at ~100 FPS (one frame every 10 ms).
    let max_fps: f64 = 1.0 / 100.0;

    // -- Main loop ----------------------------------------------------------
    while shared.loop_running.load(Ordering::SeqCst) {
        // Pop the most recent message (back of the vector, matching C++ behaviour).
        let msg = {
            let mut msgs = shared.messages.lock().unwrap();
            msgs.pop()
        };

        match msg {
            Some(Message::StopRenderer) => {
                shared.loop_running.store(false, Ordering::SeqCst);
                break;
            }

            Some(Message::NewShader) => {
                // Drop old shader (releases its GL resources and glow::Context).
                shader = None;

                let vert = shared.new_vertex_source.lock().unwrap().clone();
                let frag = shared.new_fragment_source.lock().unwrap().clone();
                let is_continuous =
                    shared.new_is_continuous.load(Ordering::SeqCst);
                let is_toy = shared.is_shader_toy.load(Ordering::SeqCst);

                // GL context must be current to create the glow function table.
                platform.make_current();
                let gl = unsafe { create_gl_context(&platform) };

                let mut s = Shader::new(
                    gl,
                    shared.width,
                    shared.height,
                    shared.texture_name,
                    shared.uses_fbo,
                );
                s.set_shaders_text(vert, frag);
                s.set_shaders_size(shared.width, shared.height);
                s.set_is_continuous(is_continuous);

                let error = if is_toy {
                    s.init_shader_toy()
                } else {
                    s.init_shader()
                };

                // Mirror shader metadata into shared state for cross-thread queries.
                *shared.compile_error.lock().unwrap() = error;
                *shared.current_vertex_source.lock().unwrap() =
                    s.vertex_source().to_string();
                *shared.current_fragment_source.lock().unwrap() =
                    s.fragment_source().to_string();
                shared
                    .shader_valid
                    .store(s.is_valid(), Ordering::SeqCst);
                shared
                    .shader_continuous
                    .store(s.is_continuous(), Ordering::SeqCst);
                *shared.shader_width.lock().unwrap() = s.width();
                *shared.shader_height.lock().unwrap() = s.height();

                shader = Some(s);
                shared.shader_compiled.store(true, Ordering::SeqCst);
            }

            Some(Message::NewTexture) => {
                if let Some(ref mut s) = shader {
                    platform.make_current();
                    // Use loop_gl to avoid simultaneous &self / &mut self
                    // borrows on the Shader (uniforms_mut + gl).
                    s.uniforms_mut().set_all_sampler2d(&loop_gl);
                    platform.clear_context();
                }
            }

            Some(Message::DeleteTexture(tex_id)) => {
                if let Some(nz) = std::num::NonZeroU32::new(tex_id) {
                    platform.make_current();
                    unsafe {
                        loop_gl.delete_texture(glow::NativeTexture(nz));
                    }
                    platform.clear_context();
                }
            }

            Some(Message::SetTexture {
                n_texture,
                texture_index,
                width,
                height,
                data,
            }) => {
                platform.make_current();
                unsafe {
                    loop_gl
                        .active_texture(glow::TEXTURE0 + n_texture as u32);
                    if let Some(nz) =
                        std::num::NonZeroU32::new(texture_index)
                    {
                        loop_gl.bind_texture(
                            glow::TEXTURE_2D,
                            Some(glow::NativeTexture(nz)),
                        );
                    }
                    loop_gl.tex_sub_image_2d(
                        glow::TEXTURE_2D,
                        0,
                        0,
                        0,
                        width,
                        height,
                        glow::RGBA,
                        glow::UNSIGNED_BYTE,
                        glow::PixelUnpackData::Slice(Some(&data)),
                    );
                }
                platform.clear_context();
            }

            None => {
                // No message -- render a frame if the shader is continuous.
                let s = match shader.as_mut() {
                    Some(s) if s.is_continuous() => s,
                    _ => continue,
                };

                // Apply any pending uniform operations from the FFI thread.
                // Some ops (AddSampler2D, ReplaceSampler2D, NewTexture) need
                // an active GL context for texture uploads.
                {
                    let mut ops =
                        shared.pending_uniform_ops.lock().unwrap();
                    if !ops.is_empty() {
                        platform.make_current();
                        apply_uniform_ops(s, &mut ops, &loop_gl);
                        platform.clear_context();
                    }
                }

                // Frame-rate limiting.
                end_draw = Instant::now();
                let elapsed_draw = end_draw
                    .duration_since(start_draw)
                    .as_secs_f64();

                if elapsed_draw >= max_fps {
                    frames += 1;
                    s.draw_frame(&platform);
                    start_draw = Instant::now();
                }

                // Update reported frame-rate roughly once per second.
                end_fps = Instant::now();
                let elapsed_fps =
                    end_fps.duration_since(start_fps).as_secs_f64();

                if elapsed_fps >= 1.0 {
                    frame_rate =
                        frames as f64 * 0.5 + frame_rate * 0.5;
                    frames = 0;
                    start_fps = Instant::now();
                    *shared.frame_rate.lock().unwrap() = frame_rate;
                }
            }
        }
    }

    // -- Cleanup ------------------------------------------------------------
    // Drop shader (releases its glow::Context and GL resources).
    drop(shader);

    // Return the platform context so the caller can reuse or drop it.
    *shared.platform.lock().unwrap() = Some(platform);
    shared.loop_running.store(false, Ordering::SeqCst);
}
