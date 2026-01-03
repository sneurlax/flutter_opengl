#import "FlutterOpenglTexture.h"
#include <cstring>

@implementation FlutterOpenglTexture

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
        _buffer = new uint8_t[width * height * 4]();
    }
    return self;
}

- (void)dealloc {
    if (_buffer) {
        delete[] _buffer;
        _buffer = nullptr;
    }
}

// Called by Flutter engine to get the pixel data for this texture.
// Returns a CVPixelBuffer copied from our CPU-side RGBA buffer.
- (CVPixelBufferRef)copyPixelBuffer {
    if (!_buffer) return NULL;

    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *attrs = @{
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    CVReturn status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        _width,
        _height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attrs,
        &pixelBuffer
    );

    if (status != kCVReturnSuccess || !pixelBuffer) {
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *dst = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t dstBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    size_t srcBytesPerRow = _width * 4;

    // Copy row-by-row, converting RGBA -> BGRA in-place
    uint8_t *srcRow = _buffer;
    uint8_t *dstRow = (uint8_t *)dst;
    for (uint32_t y = 0; y < _height; y++) {
        for (uint32_t x = 0; x < _width; x++) {
            uint32_t si = x * 4;
            uint32_t di = x * 4;
            dstRow[di + 0] = srcRow[si + 2]; // B <- R
            dstRow[di + 1] = srcRow[si + 1]; // G <- G
            dstRow[di + 2] = srcRow[si + 0]; // R <- B
            dstRow[di + 3] = srcRow[si + 3]; // A <- A
        }
        srcRow += srcBytesPerRow;
        dstRow += dstBytesPerRow;
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    return pixelBuffer;
}

@end
