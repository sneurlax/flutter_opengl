#[cfg(not(target_arch = "wasm32"))]
mod platform;
mod sampler;
mod shader;
mod uniform;
#[cfg(not(target_arch = "wasm32"))]
mod renderer;

#[cfg(not(target_arch = "wasm32"))]
mod ffi;

#[cfg(target_arch = "wasm32")]
mod wasm;

#[cfg(not(target_arch = "wasm32"))]
pub use platform::PlatformContext;
#[cfg(not(target_arch = "wasm32"))]
pub use renderer::Renderer;
pub use shader::Shader;
pub use uniform::{UniformQueue, UniformType};
pub use sampler::Sampler2D;
