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

  # Plugin Obj-C++ sources
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

  # The build_rust.sh script places the universal library here.
  rust_lib_dir = '${PODS_TARGET_SRCROOT}/../rust/target/ios-universal'

  s.pod_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GL_SILENCE_DEPRECATION=1',
    'GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS' => 'NO',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "' + rust_lib_dir + '/$(CONFIGURATION)"',
    # Pass the Rust .a as an additional input to libtool so its symbols
    # are included in the pod's static framework archive
    'OTHER_LIBTOOLFLAGS' => '"' + rust_lib_dir + '/$(CONFIGURATION)/libflutter_opengl_rust.a"',
  }

  s.dependency 'Flutter'
  s.frameworks = 'OpenGLES', 'CoreVideo', 'QuartzCore'

  s.static_framework = true
end
