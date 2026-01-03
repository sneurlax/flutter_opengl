Pod::Spec.new do |s|
  s.name             = 'flutter_opengl'
  s.version          = '0.10.0'
  s.summary          = 'Flutter OpenGL plugin for macOS'
  s.description      = 'Flutter plugin to bind a Texture widget to an OpenGL context on macOS.'
  s.homepage         = 'https://github.com/alnitak/flutter_opengl'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'alnitak' => '' }
  s.source           = { :path => '.' }

  s.platform = :osx, '10.15'
  s.osx.deployment_target = '10.15'

  # Plugin Obj-C++ sources (SharedSourcesWrapper.mm #includes the C++ files)
  s.source_files = 'Classes/**/*.{h,mm,m}'
  s.public_header_files = 'Classes/FlutterOpenglPlugin.h'

  # Keep src/ headers accessible but don't try to compile them directly
  s.preserve_paths = '../src/**/*'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) _IS_MACOS_=1 GL_SILENCE_DEPRECATION=1',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/../src" "$(PODS_TARGET_SRCROOT)/../src/glm"',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -std=c++17',
    # Suppress warnings from third-party GLM headers and legacy OpenGL deprecation
    'GCC_WARN_INHIBIT_ALL_WARNINGS' => 'YES',
    'CLANG_WARN_DOCUMENTATION_COMMENTS' => 'NO',
    'GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS' => 'NO',
  }

  s.dependency 'FlutterMacOS'
  s.frameworks = 'FlutterMacOS', 'OpenGL', 'CoreVideo'
end
