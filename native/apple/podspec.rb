require 'fileutils'

module QfliPythonNative
  SHARED_SOURCES = %w[
    qfli_py_hal.c
    qfli_py_stdio.c
    qfli_py_file.c
    qfli_py_bridge.c
    qfli_py_platform.c
    qfli_py_reader.c
    qfli_py_ffi.c
  ].freeze

  TEXTUAL_SOURCES = %r{/(?:lib/re1\.5/|port/qfli_time_localtime\.c$|shared/runtime/sys_stdio_mphal\.c$)}

  def self.configure(spec, platform, podspec_dir)
    native_dir = File.realpath(File.join(podspec_dir, '..'))
    embed_dir = File.join(native_dir, 'micropython_embed')
    embed_sources = Dir[File.join(embed_dir, '*/*.c')] +
                    Dir[File.join(embed_dir, '*/*/*.c')]
    if embed_sources.reject { |path| path.match?(TEXTUAL_SOURCES) }.length < 100
      raise 'The tracked MicroPython embedding package is incomplete'
    end
    shared_sources = SHARED_SOURCES.map { |name| File.join(native_dir, 'src', name) }
    shared_sources.each do |path|
      raise "Missing shared C source: #{path}" unless File.file?(path)
    end
    headers = Dir[File.join(embed_dir, '**/*.h')] +
              Dir[File.join(native_dir, 'src/*.h')]
    sources = (embed_sources + shared_sources + headers).uniq.sort

    # Local path pods skip prepare_command and cannot select ../ source paths.
    # Stage separate compilation units inside the pod root when loading it.
    staged_prefix = 'Classes/build/qfli_py'
    staged_sources = sources.map do |source|
      relative = source.delete_prefix("#{native_dir}/")
      relative_target = File.join(staged_prefix, relative)
      target = File.join(podspec_dir, relative_target)
      FileUtils.mkdir_p(File.dirname(target))
      if !File.file?(target) || File.binread(source) != File.binread(target)
        FileUtils.cp(source, target)
      end
      relative_target
    end

    spec.name = 'qfli_python_native'
    spec.version = '1.0.0'
    spec.summary = 'Shared MicroPython C runtime for QFLIPyFlow.'
    spec.description = 'Packages the tracked upstream compiler, VM and QFLIPyFlow C port for Dart FFI.'
    spec.homepage = 'https://micropython.org'
    spec.author = 'QFLIStudio'
    spec.license = {
      :type => 'Proprietary',
      :text => 'QFLIPyFlow app packaging. Embedded MicroPython files retain their upstream license notices.'
    }
    spec.source = { :path => '.' }
    spec.source_files = staged_sources.reject { |path| path.match?(TEXTUAL_SOURCES) }
    spec.private_header_files = staged_sources.select { |path| path.end_with?('.h') }
    spec.preserve_paths = "#{staged_prefix}/**/*"
    spec.static_framework = true
    spec.libraries = 'm', 'pthread'
    spec.compiler_flags = '-Wno-unused-parameter -Wno-error=format-security'
    spec.pod_target_xcconfig = {
      'DEFINES_MODULE' => 'NO',
      'GCC_C_LANGUAGE_STANDARD' => 'gnu99',
      'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) NDEBUG MICROPY_GCREGS_SETJMP=1 MICROPY_NLR_SETJMP=1',
      'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO',
      'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Classes/build/qfli_py/micropython_embed" "$(PODS_TARGET_SRCROOT)/Classes/build/qfli_py/micropython_embed/port" "$(PODS_TARGET_SRCROOT)/Classes/build/qfli_py/src"'
    }
    # These flags belong on the app link, where static archive dead stripping occurs.
    spec.user_target_xcconfig = {
      'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_qfli_py_run_into -Wl,-u,_qfli_py_result_free -Wl,-u,_qfli_py_version'
    }

    case platform
    when :ios
      spec.dependency 'Flutter'
      spec.platform = :ios, '13.0'
      spec.pod_target_xcconfig['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'i386'
    when :macos
      spec.dependency 'FlutterMacOS'
      spec.platform = :osx, '10.15'
    else
      raise "Unsupported CocoaPods platform: #{platform}"
    end
  end
end
