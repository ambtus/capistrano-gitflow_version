# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "capistrano/gitflow_version/version"

Gem::Specification.new do |s|
  s.name        = "capistrano-gitflow_version"
  s.version     = Capistrano::GitflowVersion::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Joshua Nichols", "Alice Brown"]
  s.email       = ["josh@technicalpickles.com", "alice@alum.mit.edu"]
  s.homepage    = "https://github.com/ambtus/capistrano-gitflow"
  s.summary     = %q{Capistrano recipe for tagged deployment}
  s.description = %q{Capistrano recipe for a deployment workflow based on git tags in MAJOR.MINOR.REVISION.BUILD format}

  s.rubyforge_project = "capistrano-gitflow_version"

  s.add_dependency('capistrano-ext', '>=1.2.1')
  s.add_dependency('stringex')

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
