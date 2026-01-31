Pod::Spec.new do |s|
  s.name             = 'flutter_opengl'
  s.version          = '0.0.1'
  s.summary          = 'Flutter OpenGL plugin for iOS'
  s.description      = 'Flutter plugin to bind a Texture widget to an OpenGL ES context on iOS.'
  s.homepage         = 'https://github.com/alnitak/flutter_opengl'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'alnitak' => 'marco.bavagnoli@gmail.com' }
  s.source           = { :path => '.' }

  s.platform = :ios, '12.0'
  s.ios.deployment_target = '12.0'

  # Plugin Obj-C++ sources (no more C++ engine sources -- Rust handles rendering)
  s.source_files = 'Classes/**/*.{h,mm,m}'
  s.public_header_files = 'Classes/FlutterOpenglPlugin.h'

  # Keep the Rust source and build script accessible
  s.preserve_paths = '../rust/**/*', 'build_rust.sh'

  # Build the Rust static library before compiling the plugin
  s.script_phase = {
    :name => 'Build Rust Library',
    :script => '"${PODS_TARGET_SRCROOT}/build_rust.sh"',
    :execution_position => :before_compile,
    :shell_path => '/bin/bash',
  }

  # Determine the Rust output directory based on build configuration
  # The build_rust.sh script places the universal library here.
  rust_lib_dir = '${PODS_TARGET_SRCROOT}/../rust/target/ios-universal'

  s.pod_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GL_SILENCE_DEPRECATION=1',
    # Link against the Rust static library
    'OTHER_LDFLAGS' => '$(inherited) -L"' + rust_lib_dir + '/$(CONFIGURATION)" -lflutter_opengl_rust',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "' + rust_lib_dir + '/$(CONFIGURATION)"',
    # Suppress deprecation warnings for OpenGL ES
    'GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS' => 'NO',
  }

  s.dependency 'Flutter'
  s.frameworks = 'OpenGLES', 'CoreVideo', 'QuartzCore'

  # Rust standard library and system libraries needed by the static lib
  s.libraries = 'c++', 'resolv'

  # Declare the static library as a vendored library so Xcode knows to link it
  # (The actual .a is built by the script_phase before compilation)
  s.static_framework = true
end
