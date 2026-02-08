#ifndef FlutterOpenglTexture_h
#define FlutterOpenglTexture_h

#import <Flutter/Flutter.h>
#include <stdint.h>

/// A pixel-buffer-backed FlutterTexture that the Rust renderer writes
/// into via glReadPixels with GL_BGRA_EXT format.  The CVPixelBuffer is
/// permanently locked and Rust writes directly to its base address,
/// so copyPixelBuffer returns it with zero conversion overhead.
@interface FlutterOpenglTexture : NSObject <FlutterTexture>

@property (nonatomic, assign) uint32_t target;
@property (nonatomic, assign) uint32_t name;
@property (nonatomic, assign) uint32_t width;
@property (nonatomic, assign) uint32_t height;
@property (nonatomic, assign) uint8_t *buffer;
@property (nonatomic, assign) int32_t bytesPerRow;

- (instancetype)initWithTarget:(uint32_t)target
                          name:(uint32_t)name
                         width:(uint32_t)width
                        height:(uint32_t)height;

@end

#endif /* FlutterOpenglTexture_h */
