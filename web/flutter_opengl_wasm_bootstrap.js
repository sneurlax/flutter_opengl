// Bootstrap script that loads the Rust WASM module (ES module) and exposes
// its exports as globals so Dart's @JS() interop can access them.
//
// This script should be loaded from index.html BEFORE the Flutter app starts:
//   <script src="flutter_opengl_wasm_bootstrap.js" type="module"></script>

import init, { WasmRenderer } from './pkg/flutter_opengl_rust.js';

// Expose the init function and WasmRenderer class as globals for Dart interop.
window.__flutter_opengl_wasm_init = init;
window.__flutter_opengl_WasmRenderer = WasmRenderer;
