// This file is intentionally kept minimal.
//
// The macOS bridge callbacks (macos_make_current, macos_clear_context, etc.)
// are defined as static inline functions in macos_bridge.h, following the
// same pattern as the Linux rust_bridge.h. They are compiled into any
// translation unit that includes the header (i.e. FlutterOpenglPlugin.mm).
//
// Previously this file contained macosGetTextureBuffer() and
// macosMarkTextureFrameAvailable() which have been replaced by the
// PlatformContext callback mechanism used by the Rust engine.

#import "macos_bridge.h"
