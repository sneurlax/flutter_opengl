#ifndef FlutterOpenglTexture_h
#define FlutterOpenglTexture_h

#import <FlutterMacOS/FlutterMacOS.h>
#include <stdint.h>

// A pixel-buffer-backed FlutterTexture that the shared C++ renderer
// writes into via glReadPixels, mirroring the Linux FlPixelBufferTexture
// approach.
@interface FlutterOpenglTexture : NSObject <FlutterTexture>

@property (nonatomic, assign) uint32_t target;
@property (nonatomic, assign) uint32_t name;
@property (nonatomic, assign) uint32_t width;
@property (nonatomic, assign) uint32_t height;
@property (nonatomic, assign) uint8_t *buffer;

- (instancetype)initWithTarget:(uint32_t)target
                          name:(uint32_t)name
                         width:(uint32_t)width
                        height:(uint32_t)height;

@end

#endif /* FlutterOpenglTexture_h */
