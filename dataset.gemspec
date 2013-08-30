# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "opentox-dataset"
  s.version     = File.read("./VERSION")
  s.authors     = ["Christoph Helma"]
  s.email       = ["helma@in-silico.ch"]
  s.homepage    = "http://github.com/opentox/dataset"
  s.summary     = %q{OpenTox Dataset Service}
  s.description = %q{OpenTox Dataset Service}
  s.license     = 'GPL-3'

  s.rubyforge_project = "dataset"

  s.files         = `git ls-files`.split("\n")
  s.required_ruby_version = '>= 1.9.2'

  # specify any dependencies here; for example:
  s.add_runtime_dependency "opentox-server"
  s.add_runtime_dependency 'roo', "=1.10.1" # 1.10.2 is defunct
  s.add_runtime_dependency 'rubyzip', "=0.9.9" # roo 1.10.1 do not work with rubyzip 1.0.0
  s.add_runtime_dependency "openbabel"#, "~>2.3.1.5"
  s.post_install_message = "Please configure your service in ~/.opentox/config/dataset.rb"
end
