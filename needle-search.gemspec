# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'needle/search/version'

Gem::Specification.new do |spec|
  spec.name          = "needle-search"
  spec.version       = Needle::Search::VERSION
  spec.authors       = ["Nick Zadrozny"]
  spec.email         = ["nick@beyondthepath.com"]
  spec.description   = %q{Needle is a small and opinionated search client for Ruby applications.}
  spec.summary       = %q{A small, opinionated search client that gets right to the point.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
