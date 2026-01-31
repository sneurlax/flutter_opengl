Pod::Spec.new do |s|
  s.name             = 'flutter_opengl'
  s.version          = '0.0.1'
  s.summary          = 'Flutter OpenGL plugin for macOS'
  s.description      = 'Flutter plugin to bind a Texture widget to an OpenGL context on macOS.'
  s.homepage         = 'https://github.com/alnitak/flutter_opengl'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'alnitak' => 'marco.bavagnoli@gmail.com' }
  s.source           = { :path => '.' }

  s.platform = :osx, '10.15'
  s.osx.deployment_target = '10.15'

  # Plugin Obj-C++ sources (no more shared C++ engine sources)
  s.source_files = 'Classes/**/*.{h,mm,m}'
  s.public_header_files = 'Classes/FlutterOpenglPlugin.h'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GL_SILENCE_DEPRECATION=1',
    'OTHER_LDFLAGS' => '$(inherited) -L${PODS_TARGET_SRCROOT}/../rust/target/release -lflutter_opengl_rust',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../rust/target/release" "${PODS_TARGET_SRCROOT}/../rust/target/debug"',
    # Suppress warnings from legacy OpenGL deprecation
    'GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS' => 'NO',
  }

  # Build the Rust shared library before compiling the plugin
  s.script_phase = {
    :name => 'Build Rust Library',
    :script => <<-SCRIPT
      set -e
      RUST_DIR="${PODS_TARGET_SRCROOT}/../rust"
      if [ "${CONFIGURATION}" = "Release" ]; then
        RUST_PROFILE="release"
        CARGO_FLAGS="--release"
      else
        RUST_PROFILE="debug"
        CARGO_FLAGS=""
      fi

      # Determine the Rust target triple for the current architecture
      if [ "${ARCHS}" = "arm64" ]; then
        RUST_TARGET="aarch64-apple-darwin"
      else
        RUST_TARGET="x86_64-apple-darwin"
      fi

      echo "Building Rust library for ${RUST_TARGET} (${RUST_PROFILE})..."
      cd "${RUST_DIR}"
      cargo build ${CARGO_FLAGS} --target "${RUST_TARGET}"

      # Copy the dylib to the profile directory for linking
      RUST_LIB_SRC="${RUST_DIR}/target/${RUST_TARGET}/${RUST_PROFILE}/libflutter_opengl_rust.dylib"
      RUST_LIB_DST="${RUST_DIR}/target/${RUST_PROFILE}/libflutter_opengl_rust.dylib"
      mkdir -p "${RUST_DIR}/target/${RUST_PROFILE}"
      if [ -f "${RUST_LIB_SRC}" ]; then
        cp -f "${RUST_LIB_SRC}" "${RUST_LIB_DST}"
      fi
    SCRIPT
    ,
    :execution_position => :before_compile,
    :shell_path => '/bin/sh',
  }

  s.dependency 'FlutterMacOS'
  s.frameworks = 'FlutterMacOS', 'OpenGL', 'CoreVideo'
end
