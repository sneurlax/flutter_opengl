use std::collections::BTreeMap;
use std::os::raw::c_void;

use glow::HasContext;

use super::sampler::Sampler2D;

#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UniformType {
    Bool = 0,
    Int = 1,
    Float = 2,
    Vec2 = 3,
    Vec3 = 4,
    Vec4 = 5,
    Mat2 = 6,
    Mat3 = 7,
    Mat4 = 8,
    Sampler2D = 9,
}

impl UniformType {
    pub fn from_i32(v: i32) -> Option<Self> {
        match v {
            0 => Some(Self::Bool),
            1 => Some(Self::Int),
            2 => Some(Self::Float),
            3 => Some(Self::Vec2),
            4 => Some(Self::Vec3),
            5 => Some(Self::Vec4),
            6 => Some(Self::Mat2),
            7 => Some(Self::Mat3),
            8 => Some(Self::Mat4),
            9 => Some(Self::Sampler2D),
            _ => None,
        }
    }
}

pub enum UniformValue {
    Bool(bool),
    Int(i32),
    Float(f32),
    Vec2([f32; 2]),
    Vec3([f32; 3]),
    Vec4([f32; 4]),
    Mat2([f32; 4]),
    Mat3([f32; 9]),
    Mat4([f32; 16]),
    Sampler2D(Sampler2D),
}

pub struct UniformQueue {
    uniforms: BTreeMap<String, UniformValue>,
    program: Option<glow::NativeProgram>,
}

impl UniformQueue {
    pub fn new() -> Self {
        Self {
            uniforms: BTreeMap::new(),
            program: None,
        }
    }

    pub fn set_program(&mut self, program: glow::NativeProgram) {
        self.program = Some(program);
    }

    /// Add a uniform from a raw pointer, matching the C++ void* interface.
    /// Returns false if the name already exists.
    pub fn add_uniform(
        &mut self,
        name: &str,
        uniform_type: UniformType,
        val_ptr: *const c_void,
    ) -> bool {
        if self.uniforms.contains_key(name) {
            return false;
        }

        let value = unsafe { read_uniform_value(uniform_type, val_ptr) };
        self.uniforms.insert(name.to_string(), value);
        true
    }

    /// Remove a uniform. If it is a Sampler2D and renderer is not running,
    /// delete the GL texture directly.
    pub fn remove_uniform(
        &mut self,
        name: &str,
        gl: &glow::Context,
        renderer_running: bool,
    ) -> bool {
        if let Some(value) = self.uniforms.remove(name) {
            if let UniformValue::Sampler2D(sampler) = &value {
                if !renderer_running {
                    if let Some(texture) = sampler.texture {
                        unsafe {
                            gl.delete_texture(texture);
                        }
                    }
                }
            }
            true
        } else {
            false
        }
    }

    /// Update an existing uniform's value from a raw pointer.
    /// For Sampler2D, val_ptr is treated as raw RGBA pixel data.
    pub fn set_uniform_value(&mut self, name: &str, val_ptr: *const c_void) -> bool {
        let Some(existing) = self.uniforms.get_mut(name) else {
            return false;
        };

        unsafe {
            match existing {
                UniformValue::Sampler2D(sampler) => {
                    let data_ptr = val_ptr as *const u8;
                    let byte_count = (sampler.width * sampler.height * 4) as usize;
                    let data = std::slice::from_raw_parts(data_ptr, byte_count);
                    sampler.add_rgba32(sampler.width, sampler.height, data);
                }
                _ => {
                    let float_ptr = val_ptr as *const f32;
                    match existing {
                        UniformValue::Bool(v) => *v = *float_ptr != 0.0,
                        UniformValue::Int(v) => *v = *float_ptr as i32,
                        UniformValue::Float(v) => *v = *float_ptr,
                        UniformValue::Vec2(v) => {
                            std::ptr::copy_nonoverlapping(float_ptr, v.as_mut_ptr(), 2);
                        }
                        UniformValue::Vec3(v) => {
                            std::ptr::copy_nonoverlapping(float_ptr, v.as_mut_ptr(), 3);
                        }
                        UniformValue::Vec4(v) => {
                            std::ptr::copy_nonoverlapping(float_ptr, v.as_mut_ptr(), 4);
                        }
                        UniformValue::Mat2(v) => {
                            std::ptr::copy_nonoverlapping(float_ptr, v.as_mut_ptr(), 4);
                        }
                        UniformValue::Mat3(v) => {
                            std::ptr::copy_nonoverlapping(float_ptr, v.as_mut_ptr(), 9);
                        }
                        UniformValue::Mat4(v) => {
                            std::ptr::copy_nonoverlapping(float_ptr, v.as_mut_ptr(), 16);
                        }
                        UniformValue::Sampler2D(_) => unreachable!(),
                    }
                }
            }
        }

        true
    }

    /// Send all uniforms to the GPU via the appropriate glUniform* calls.
    pub fn send_all_uniforms(&self, gl: &glow::Context) {
        let program = match self.program {
            Some(p) => p,
            None => return,
        };

        for (name, value) in &self.uniforms {
            let location = unsafe { gl.get_uniform_location(program, name) };

            unsafe {
                match value {
                    UniformValue::Bool(v) => {
                        gl.uniform_1_i32(location.as_ref(), if *v { 1 } else { 0 });
                    }
                    UniformValue::Int(v) => {
                        gl.uniform_1_i32(location.as_ref(), *v);
                    }
                    UniformValue::Float(v) => {
                        gl.uniform_1_f32(location.as_ref(), *v);
                    }
                    UniformValue::Vec2(v) => {
                        gl.uniform_2_f32_slice(location.as_ref(), v);
                    }
                    UniformValue::Vec3(v) => {
                        gl.uniform_3_f32_slice(location.as_ref(), v);
                    }
                    UniformValue::Vec4(v) => {
                        gl.uniform_4_f32_slice(location.as_ref(), v);
                    }
                    UniformValue::Mat2(v) => {
                        gl.uniform_matrix_2_f32_slice(location.as_ref(), false, v);
                    }
                    UniformValue::Mat3(v) => {
                        gl.uniform_matrix_3_f32_slice(location.as_ref(), false, v);
                    }
                    UniformValue::Mat4(v) => {
                        gl.uniform_matrix_4_f32_slice(location.as_ref(), false, v);
                    }
                    UniformValue::Sampler2D(sampler) => {
                        if sampler.n_texture != -1 {
                            let n = sampler.n_texture as u32;
                            gl.active_texture(glow::TEXTURE0 + n);
                            gl.bind_texture(glow::TEXTURE_2D, sampler.texture);
                            gl.uniform_1_i32(location.as_ref(), sampler.n_texture);
                        }
                    }
                }
            }
        }
    }

    /// Assign texture units to unassigned samplers and generate textures.
    /// Scans texture units 0..31 to find free slots.
    pub fn set_all_sampler2d(&mut self, gl: &glow::Context) {
        // Collect which texture units are already in use.
        let mut used_units: Vec<i32> = Vec::new();
        for value in self.uniforms.values() {
            if let UniformValue::Sampler2D(sampler) = value {
                if sampler.n_texture != -1 {
                    used_units.push(sampler.n_texture);
                }
            }
        }

        for value in self.uniforms.values_mut() {
            if let UniformValue::Sampler2D(sampler) = value {
                if sampler.n_texture == -1 {
                    // Find a free texture unit.
                    let mut unit = -1i32;
                    for candidate in 0..32 {
                        if !used_units.contains(&candidate) {
                            unit = candidate;
                            break;
                        }
                    }
                    if unit != -1 {
                        used_units.push(unit);
                        sampler.gen_texture(gl, unit);
                    }
                }
            }
        }
    }

    /// Replace texture data on an existing Sampler2D uniform.
    pub fn replace_sampler2d(&mut self, name: &str, w: i32, h: i32, data: &[u8]) -> bool {
        if let Some(UniformValue::Sampler2D(sampler)) = self.uniforms.get_mut(name) {
            sampler.replace_texture(w, h, data);
            true
        } else {
            false
        }
    }

    /// Get a mutable reference to a Sampler2D if it exists.
    pub fn get_sampler2d(&mut self, name: &str) -> Option<&mut Sampler2D> {
        if let Some(UniformValue::Sampler2D(sampler)) = self.uniforms.get_mut(name) {
            Some(sampler)
        } else {
            None
        }
    }
}

/// Read a `UniformValue` from a raw pointer based on the given type.
///
/// # Safety
/// The caller must ensure `val_ptr` points to valid memory of the correct type.
unsafe fn read_uniform_value(uniform_type: UniformType, val_ptr: *const c_void) -> UniformValue {
    match uniform_type {
        UniformType::Bool => {
            let v = *(val_ptr as *const bool);
            UniformValue::Bool(v)
        }
        UniformType::Int => {
            let v = *(val_ptr as *const i32);
            UniformValue::Int(v)
        }
        UniformType::Float => {
            let v = *(val_ptr as *const f32);
            UniformValue::Float(v)
        }
        UniformType::Vec2 => {
            let p = val_ptr as *const f32;
            let mut v = [0.0f32; 2];
            std::ptr::copy_nonoverlapping(p, v.as_mut_ptr(), 2);
            UniformValue::Vec2(v)
        }
        UniformType::Vec3 => {
            let p = val_ptr as *const f32;
            let mut v = [0.0f32; 3];
            std::ptr::copy_nonoverlapping(p, v.as_mut_ptr(), 3);
            UniformValue::Vec3(v)
        }
        UniformType::Vec4 => {
            let p = val_ptr as *const f32;
            let mut v = [0.0f32; 4];
            std::ptr::copy_nonoverlapping(p, v.as_mut_ptr(), 4);
            UniformValue::Vec4(v)
        }
        UniformType::Mat2 => {
            let p = val_ptr as *const f32;
            let mut v = [0.0f32; 4];
            std::ptr::copy_nonoverlapping(p, v.as_mut_ptr(), 4);
            UniformValue::Mat2(v)
        }
        UniformType::Mat3 => {
            let p = val_ptr as *const f32;
            let mut v = [0.0f32; 9];
            std::ptr::copy_nonoverlapping(p, v.as_mut_ptr(), 9);
            UniformValue::Mat3(v)
        }
        UniformType::Mat4 => {
            let p = val_ptr as *const f32;
            let mut v = [0.0f32; 16];
            std::ptr::copy_nonoverlapping(p, v.as_mut_ptr(), 16);
            UniformValue::Mat4(v)
        }
        UniformType::Sampler2D => {
            let sampler_ref = &*(val_ptr as *const Sampler2D);
            // Manually clone since Sampler2D may not derive Clone.
            let mut cloned = Sampler2D::new();
            cloned.width = sampler_ref.width;
            cloned.height = sampler_ref.height;
            cloned.data = sampler_ref.data.clone();
            cloned.texture = sampler_ref.texture;
            cloned.n_texture = sampler_ref.n_texture;
            UniformValue::Sampler2D(cloned)
        }
    }
}
