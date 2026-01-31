use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::sync::Mutex;

use crate::platform::PlatformContext;
use crate::renderer::Renderer;
use crate::sampler::Sampler2D;
use crate::uniform::UniformType;

static RENDERER: Mutex<Option<Renderer>> = Mutex::new(None);
static COMPILE_ERROR: Mutex<Option<CString>> = Mutex::new(None);
static VERTEX_SOURCE: Mutex<Option<CString>> = Mutex::new(None);
static FRAGMENT_SOURCE: Mutex<Option<CString>> = Mutex::new(None);

fn store_and_return_cstring(s: String, storage: &Mutex<Option<CString>>) -> *const c_char {
    let cstr = CString::new(s).unwrap_or_default();
    let ptr = cstr.as_ptr();
    *storage.lock().unwrap() = Some(cstr);
    ptr
}

fn empty_cstr() -> *const c_char {
    static EMPTY: &[u8] = b"\0";
    EMPTY.as_ptr() as *const c_char
}

// ---------------------------------------------------------------------------
// Renderer lifecycle
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn createRenderer(ctx: *mut PlatformContext) {
    // Tear down any previous renderer first.
    deleteRenderer();
    let platform = std::ptr::read(ctx);
    *RENDERER.lock().unwrap() = Some(Renderer::new(platform));
}

#[no_mangle]
pub unsafe extern "C" fn deleteRenderer() {
    let mut guard = RENDERER.lock().unwrap();
    if let Some(renderer) = guard.as_ref() {
        if renderer.is_looping() {
            renderer.stop();
            while renderer.is_looping() {
                std::thread::yield_now();
            }
        }
    }
    *guard = None;
}

#[no_mangle]
pub unsafe extern "C" fn getRenderer() -> *mut c_void {
    let guard = RENDERER.lock().unwrap();
    if guard.is_some() {
        1usize as *mut c_void
    } else {
        std::ptr::null_mut()
    }
}

#[no_mangle]
pub unsafe extern "C" fn rendererStatus() -> bool {
    RENDERER.lock().unwrap().is_some()
}

// ---------------------------------------------------------------------------
// Texture queries
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn getTextureSize(width: *mut i32, height: *mut i32) {
    let guard = RENDERER.lock().unwrap();
    match guard.as_ref() {
        Some(r) if r.has_shader() => {
            *width = r.get_shader_width();
            *height = r.get_shader_height();
        }
        _ => {
            *width = -1;
            *height = -1;
        }
    }
}

// ---------------------------------------------------------------------------
// Thread control
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn startThread() {
    let guard = RENDERER.lock().unwrap();
    if let Some(r) = guard.as_ref() {
        r.start_thread();
    }
}

/// Stop the render loop and destroy the renderer.
#[no_mangle]
pub unsafe extern "C" fn stopThread() {
    let mut guard = RENDERER.lock().unwrap();
    if let Some(renderer) = guard.as_ref() {
        renderer.stop();
        while renderer.is_looping() {
            std::thread::yield_now();
        }
    }
    *guard = None;
}

// ---------------------------------------------------------------------------
// Shader compilation
// ---------------------------------------------------------------------------

/// Set a new vertex + fragment shader pair. Blocks until the render thread has
/// compiled them. Returns a pointer to the compile-error string (empty on
/// success). The pointer is valid until the next `setShader` / `setShaderToy`.
#[no_mangle]
pub unsafe extern "C" fn setShader(
    isContinuous: bool,
    vertexShader: *const c_char,
    fragmentShader: *const c_char,
) -> *const c_char {
    let v = CStr::from_ptr(vertexShader).to_string_lossy().into_owned();
    let f = CStr::from_ptr(fragmentShader).to_string_lossy().into_owned();

    let error = {
        let guard = RENDERER.lock().unwrap();
        match guard.as_ref() {
            Some(r) => {
                let shared = r.shared_handle();
                drop(guard); // release lock before blocking spin-wait
                Renderer::set_shader_blocking(&shared, isContinuous, &v, &f)
            }
            None => String::new(),
        }
    };

    store_and_return_cstring(error, &COMPILE_ERROR)
}

/// Set a ShaderToy-style fragment shader. The vertex shader and wrapping
/// `main()` are generated automatically. Blocks until compiled.
#[no_mangle]
pub unsafe extern "C" fn setShaderToy(
    fragmentShader: *const c_char,
) -> *const c_char {
    let f = CStr::from_ptr(fragmentShader).to_string_lossy().into_owned();

    let error = {
        let guard = RENDERER.lock().unwrap();
        match guard.as_ref() {
            Some(r) => {
                let shared = r.shared_handle();
                drop(guard);
                Renderer::set_shader_toy_blocking(&shared, &f)
            }
            None => String::new(),
        }
    };

    store_and_return_cstring(error, &COMPILE_ERROR)
}

// ---------------------------------------------------------------------------
// Shader source queries
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn getVertexShader() -> *const c_char {
    let guard = RENDERER.lock().unwrap();
    match guard.as_ref() {
        Some(r) => {
            let src = r.get_vertex_source();
            drop(guard);
            store_and_return_cstring(src, &VERTEX_SOURCE)
        }
        None => empty_cstr(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn getFragmentShader() -> *const c_char {
    let guard = RENDERER.lock().unwrap();
    match guard.as_ref() {
        Some(r) => {
            let src = r.get_fragment_source();
            drop(guard);
            store_and_return_cstring(src, &FRAGMENT_SOURCE)
        }
        None => empty_cstr(),
    }
}

// ---------------------------------------------------------------------------
// ShaderToy uniforms
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn addShaderToyUniforms() {
    let guard = RENDERER.lock().unwrap();
    if let Some(r) = guard.as_ref() {
        r.add_shader_toy_uniforms();
    }
}

// ---------------------------------------------------------------------------
// Mouse / interaction
// ---------------------------------------------------------------------------

/// Update the `iMouse` uniform, normalising the coordinates from the Flutter
/// `Texture` widget size to the actual shader texture size.
#[no_mangle]
pub unsafe extern "C" fn setMousePosition(
    mut posX: f64,
    mut posY: f64,
    mut posZ: f64,
    mut posW: f64,
    textureWidgetWidth: f64,
    textureWidgetHeight: f64,
) {
    let guard = RENDERER.lock().unwrap();
    let r = match guard.as_ref() {
        Some(r) if r.has_shader() => r,
        _ => return,
    };

    let texture_width = r.get_shader_width() as f64;
    let texture_height = r.get_shader_height() as f64;

    let ar_h = texture_width / textureWidgetWidth;
    let ar_v = texture_height / textureWidgetHeight;

    posX *= ar_h;
    posY *= ar_v;
    posZ *= ar_h;
    posW *= ar_v;

    // Flip Y vertically (matches C++ behaviour).
    posY = texture_height - posY;
    posW = -texture_height - posW;

    r.set_mouse_position(posX as f32, posY as f32, posZ as f32, posW as f32);
}

// ---------------------------------------------------------------------------
// FPS
// ---------------------------------------------------------------------------

/// Return the current measured frame rate, or -1.0 when the renderer is not
/// running.
#[no_mangle]
pub unsafe extern "C" fn getFPS() -> f64 {
    let guard = RENDERER.lock().unwrap();
    match guard.as_ref() {
        Some(r) if r.is_looping() => r.get_frame_rate(),
        _ => -1.0,
    }
}

// ---------------------------------------------------------------------------
// Generic uniforms
// ---------------------------------------------------------------------------

/// Add a uniform of the given type. `val` points to the value data whose
/// layout must match the type (bool, i32, f32, [f32;N], or Sampler2D).
#[no_mangle]
pub unsafe extern "C" fn addUniform(
    name: *const c_char,
    uniform_type: i32,
    val: *mut c_void,
) -> bool {
    let name_str = CStr::from_ptr(name).to_string_lossy();
    let ut = match UniformType::from_i32(uniform_type) {
        Some(t) => t,
        None => return false,
    };

    let data_size = match ut {
        UniformType::Bool => std::mem::size_of::<bool>(),
        UniformType::Int => std::mem::size_of::<i32>(),
        UniformType::Float => std::mem::size_of::<f32>(),
        UniformType::Vec2 => std::mem::size_of::<[f32; 2]>(),
        UniformType::Vec3 => std::mem::size_of::<[f32; 3]>(),
        UniformType::Vec4 => std::mem::size_of::<[f32; 4]>(),
        UniformType::Mat2 => std::mem::size_of::<[f32; 4]>(),
        UniformType::Mat3 => std::mem::size_of::<[f32; 9]>(),
        UniformType::Mat4 => std::mem::size_of::<[f32; 16]>(),
        UniformType::Sampler2D => std::mem::size_of::<Sampler2D>(),
    };
    let data_vec = std::slice::from_raw_parts(val as *const u8, data_size).to_vec();

    let guard = RENDERER.lock().unwrap();
    match guard.as_ref() {
        Some(r) if r.has_shader() => {
            r.add_uniform(&name_str, ut, data_vec);
            true
        }
        _ => false,
    }
}

#[no_mangle]
pub unsafe extern "C" fn removeUniform(name: *const c_char) -> bool {
    let name_str = CStr::from_ptr(name).to_string_lossy();

    let guard = RENDERER.lock().unwrap();
    match guard.as_ref() {
        Some(r) if r.has_shader() => {
            r.remove_uniform(&name_str);
            true
        }
        _ => false,
    }
}

/// Update the value of an existing uniform. For Sampler2D the pointer is
/// treated as raw RGBA pixel data of the same dimensions.
#[no_mangle]
pub unsafe extern "C" fn setUniform(
    name: *const c_char,
    val: *mut c_void,
) -> bool {
    let name_str = CStr::from_ptr(name).to_string_lossy();

    // Copy enough bytes for the largest possible uniform value (mat4 = 64 bytes).
    // The render thread will interpret the bytes based on the uniform's stored type.
    let data_vec = std::slice::from_raw_parts(val as *const u8, 64).to_vec();

    let guard = RENDERER.lock().unwrap();
    match guard.as_ref() {
        Some(r) if r.has_shader() => {
            r.set_uniform_value(&name_str, data_vec);
            true
        }
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// Sampler2D uniforms
// ---------------------------------------------------------------------------

/// Add a new Sampler2D uniform with RGBA32 image data.
#[no_mangle]
pub unsafe extern "C" fn addSampler2DUniform(
    name: *const c_char,
    width: i32,
    height: i32,
    val: *mut c_void,
) -> bool {
    let name_str = CStr::from_ptr(name).to_string_lossy();
    let byte_count = (width * height * 4) as usize;
    let data = std::slice::from_raw_parts(val as *const u8, byte_count);

    let guard = RENDERER.lock().unwrap();
    match guard.as_ref() {
        Some(r) if r.has_shader() => {
            let mut sampler = Sampler2D::new();
            sampler.add_rgba32(width, height, data);

            r.add_sampler2d_uniform(&name_str, sampler);
            if r.is_looping() {
                r.queue_new_texture();
            }
            true
        }
        _ => false,
    }
}

/// Replace the texture data of an existing Sampler2D uniform. Use this when the
/// new image has different dimensions from the original.
#[no_mangle]
pub unsafe extern "C" fn replaceSampler2DUniform(
    name: *const c_char,
    width: i32,
    height: i32,
    val: *mut c_void,
) -> bool {
    let name_str = CStr::from_ptr(name).to_string_lossy();
    let byte_count = (width * height * 4) as usize;
    let data = std::slice::from_raw_parts(val as *const u8, byte_count);

    let guard = RENDERER.lock().unwrap();
    match guard.as_ref() {
        Some(r) if r.has_shader() => {
            r.replace_sampler2d_uniform(&name_str, width, height, data.to_vec());
            if r.is_looping() {
                r.queue_new_texture();
            }
            true
        }
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// Capture stubs (OpenCV not supported in Rust backend)
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn startCaptureOnSampler2D(
    _name: *const c_char,
    _completeFilePath: *const c_char,
) -> bool {
    false
}

#[no_mangle]
pub unsafe extern "C" fn stopCapture() -> bool {
    false
}

// ---------------------------------------------------------------------------
// Miscellaneous
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn nativeSurfaceSetClearColor(
    _r: i32,
    _g: i32,
    _b: i32,
    _a: i32,
) {
    // Reserved for future use.
}
