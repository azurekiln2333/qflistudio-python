require File.expand_path('../apple/podspec.rb', __dir__)

Pod::Spec.new do |spec|
  QfliPythonNative.configure(spec, :macos, __dir__)
end
