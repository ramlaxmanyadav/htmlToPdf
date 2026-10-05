# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'htmlToPdf/version'

Gem::Specification.new do |spec|
  spec.name          = "htmlToPdf"
  spec.version       = HtmlToPdf::VERSION
  spec.authors       = ["Ram Laxman Yadav"]
  spec.email         = ["yadavramlaxman@gmail.com"]
  spec.summary       = %q{Render Rails controller actions to PDF using headless Chrome}
  spec.description   = %q{HtmlToPdf lets any Rails controller action be downloaded as a PDF. Request the action with a PDF format and the gem renders the view exactly as the browser would, then converts it to PDF via a pooled headless Chrome instance (through the ferrum gem). Supports Rails 7.x and 8.x.}
  spec.homepage      = "https://github.com/ramlaxmanyadav/htmlToPdf"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})

  spec.add_dependency "ferrum", ">= 0.13", "< 1.0"
  spec.add_dependency "activesupport", ">= 7.0", "< 9"

  spec.metadata["source_code_uri"]   = spec.homepage
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"]   = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_development_dependency "bundler", ">= 2.4", "< 5"
  spec.add_development_dependency "rake", ">= 13.0", "< 14"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rspec-rails", "~> 7.0"
  spec.add_development_dependency "combustion", "~> 1.5"
  spec.add_development_dependency "rails", ">= 7.0", "< 9"
  spec.add_development_dependency "puma", ">= 5.0", "< 7"
end
