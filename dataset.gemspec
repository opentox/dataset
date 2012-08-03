# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "dataset"
  s.version     = File.read("./VERSION")
  s.authors     = ["Christoph Helma"]
  s.email       = ["helma@in-silico.ch"]
  s.homepage    = ""
  s.summary     = %q{OpenTox Dataset Service}
  s.description = %q{OpenTox Dataset Service}
  s.license     = 'GPL-3'

  s.rubyforge_project = "dataset"

  s.files         = `git ls-files`.split("\n")
  s.required_ruby_version = '>= 1.9.2'

  # specify any dependencies here; for example:
  s.add_runtime_dependency "opentox-server"
  s.add_runtime_dependency 'roo'
  #s.add_runtime_dependency 'axlsx'
  #s.add_runtime_dependency 'simple_xlsx_writer'
  s.post_install_message = "Please configure your service in ~/.opentox/config/dataset.rb"
end
