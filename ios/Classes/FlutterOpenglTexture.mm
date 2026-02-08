#import "FlutterOpenglTexture.h"

@implementation FlutterOpenglTexture {
    CVPixelBufferRef _pixelBuffer;
}

- (instancetype)initWithTarget:(uint32_t)target
                          name:(uint32_t)name
                         width:(uint32_t)width
                        height:(uint32_t)height {
    self = [super init];
    if (self) {
        _target = target;
        _name = name;
        _width = width;
        _height = height;

        // Create a BGRA CVPixelBuffer backed by an IOSurface.
        NSDictionary *attrs = @{
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };
        CVReturn status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            (__bridge CFDictionaryRef)attrs,
            &_pixelBuffer);
        if (status != kCVReturnSuccess) {
            _pixelBuffer = NULL;
            _buffer = nullptr;
        } else {
            // Lock the pixel buffer permanently.  Rust writes BGRA pixels
            // directly to this address via glReadPixels(GL_BGRA_EXT),
            // so no conversion is needed in copyPixelBuffer.
            CVPixelBufferLockBaseAddress(_pixelBuffer, 0);
            _buffer = (uint8_t *)CVPixelBufferGetBaseAddress(_pixelBuffer);
            _bytesPerRow = (int32_t)CVPixelBufferGetBytesPerRow(_pixelBuffer);
        }
    }
    return self;
}

- (void)dealloc {
    if (_pixelBuffer) {
        CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);
        CVPixelBufferRelease(_pixelBuffer);
        _pixelBuffer = NULL;
    }
    _buffer = nullptr;
}

// Called by Flutter engine to get the pixel data for this texture.
// The buffer already contains BGRA data written directly by Rust's
// glReadPixels(GL_BGRA_EXT), so we just retain and return.
- (CVPixelBufferRef)copyPixelBuffer {
    if (!_pixelBuffer) return NULL;
    CVPixelBufferRetain(_pixelBuffer);
    return _pixelBuffer;
}

@end
