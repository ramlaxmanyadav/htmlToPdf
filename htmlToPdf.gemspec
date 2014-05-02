# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'htmlToPdf/version'

Gem::Specification.new do |spec|
  spec.name          = "htmlToPdf"
  spec.version       = HtmlToPdf::VERSION
  spec.authors       = ["Ram Laxman Yadav"]
  spec.email         = ["yadavramlaxman@gmail.com"]
  spec.summary       = %q{html to pdf converter gem}
  spec.description   = %q{this gem will generate pdf of given html using wkhtmmltopdf}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = ["wkhtmltopdf"]
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
end
