use glow::HasContext;

pub struct Sampler2D {
    pub width: i32,
    pub height: i32,
    pub data: Vec<u8>,
    pub texture: Option<glow::Texture>,
    pub n_texture: i32,
}

impl Sampler2D {
    pub fn new() -> Self {
        Self {
            width: 0,
            height: 0,
            data: Vec::new(),
            texture: None,
            n_texture: -1,
        }
    }

    pub fn add_rgba32(&mut self, w: i32, h: i32, raw_data: &[u8]) {
        self.width = w;
        self.height = h;
        self.data.extend_from_slice(raw_data);
    }

    pub fn replace_texture(&mut self, w: i32, h: i32, raw_data: &[u8]) {
        if self.n_texture == -1 {
            return;
        }
        self.data.clear();
        self.add_rgba32(w, h, raw_data);
    }

    pub fn gen_texture(&mut self, gl: &glow::Context, n: i32) {
        if self.data.is_empty() {
            return;
        }

        if self.n_texture == -1 {
            self.n_texture = n;
            self.texture = Some(unsafe { gl.create_texture().unwrap() });
        }

        unsafe {
            gl.active_texture(glow::TEXTURE0 + self.n_texture as u32);
            gl.bind_texture(glow::TEXTURE_2D, self.texture);

            gl.tex_parameter_i32(
                glow::TEXTURE_2D,
                glow::TEXTURE_MIN_FILTER,
                glow::LINEAR_MIPMAP_LINEAR as i32,
            );
            gl.tex_parameter_i32(
                glow::TEXTURE_2D,
                glow::TEXTURE_MAG_FILTER,
                glow::LINEAR as i32,
            );
            gl.tex_parameter_i32(
                glow::TEXTURE_2D,
                glow::TEXTURE_WRAP_S,
                glow::CLAMP_TO_EDGE as i32,
            );
            gl.tex_parameter_i32(
                glow::TEXTURE_2D,
                glow::TEXTURE_WRAP_T,
                glow::CLAMP_TO_EDGE as i32,
            );

            gl.tex_image_2d(
                glow::TEXTURE_2D,
                0,
                glow::RGBA as i32,
                self.width,
                self.height,
                0,
                glow::RGBA,
                glow::UNSIGNED_BYTE,
                glow::PixelUnpackData::Slice(Some(&self.data)),
            );

            gl.generate_mipmap(glow::TEXTURE_2D);
        }
    }
}
