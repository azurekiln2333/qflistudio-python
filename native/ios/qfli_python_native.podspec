require File.expand_path('../apple/podspec.rb', __dir__)

Pod::Spec.new do |spec|
  QfliPythonNative.configure(spec, :ios, __dir__)
end
