use std::os::raw::c_void;

/// Platform-specific GL callbacks, filled in by each platform plugin.
#[repr(C)]
pub struct PlatformContext {
    /// Make the GL context current on the calling thread.
    pub make_current: Option<unsafe extern "C" fn(user_data: *mut c_void)>,
    /// Clear the current GL context from the calling thread.
    pub clear_context: Option<unsafe extern "C" fn(user_data: *mut c_void)>,
    /// Return a pointer to the CPU pixel buffer for glReadPixels output.
    /// May be null on platforms that render directly (e.g. Android swap buffers).
    pub get_pixel_buffer: Option<unsafe extern "C" fn(user_data: *mut c_void) -> *mut u8>,
    /// Notify Flutter that a new frame is available in the texture.
    pub mark_frame_available: Option<unsafe extern "C" fn(user_data: *mut c_void)>,
    /// Swap buffers (Android EGL). Null on FBO-based platforms.
    pub swap_buffers: Option<unsafe extern "C" fn(user_data: *mut c_void) -> bool>,
    /// Load a GL function pointer by name. Called once during glow::Context creation.
    pub load_gl_proc: Option<unsafe extern "C" fn(name: *const i8) -> *const c_void>,
    /// Opaque pointer passed back to every callback.
    pub user_data: *mut c_void,
    /// Texture dimensions.
    pub width: i32,
    pub height: i32,
    /// GL texture name created by the platform plugin (for FBO attachment).
    pub texture_name: u32,
    /// Whether this platform uses FBO + glReadPixels (true) or direct swap (false).
    pub uses_fbo: bool,
}

unsafe impl Send for PlatformContext {}
unsafe impl Sync for PlatformContext {}

impl PlatformContext {
    pub fn make_current(&self) {
        if let Some(f) = self.make_current {
            unsafe { f(self.user_data) };
        }
    }

    pub fn clear_context(&self) {
        if let Some(f) = self.clear_context {
            unsafe { f(self.user_data) };
        }
    }

    pub fn get_pixel_buffer(&self) -> *mut u8 {
        match self.get_pixel_buffer {
            Some(f) => unsafe { f(self.user_data) },
            None => std::ptr::null_mut(),
        }
    }

    pub fn mark_frame_available(&self) {
        if let Some(f) = self.mark_frame_available {
            unsafe { f(self.user_data) };
        }
    }

    pub fn swap_buffers(&self) -> bool {
        match self.swap_buffers {
            Some(f) => unsafe { f(self.user_data) },
            None => false,
        }
    }
}
