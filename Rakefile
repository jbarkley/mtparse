require 'rake/gempackagetask' 

spec = Gem::Specification.new do |s| 
  s.name = "mtparse"
  s.description = "Uses net/* libraries and nokogiri xml parser to reach out and retrieve .xml  files/packages conforming to the OVF spec and parse them."
  s.version = "0.1.0"
  s.author = "Jim Barkley"
  s.email = "james.barkley@uilabs.org"
  s.homepage = "http://github.com/ruby-ovf/ovfparse"
  s.platform = Gem::Platform::RUBY
  s.summary = "Retreves and parses files in the MTCOnnect Format"
  s.files = FileList["{bin,lib}/**/*"].to_a
  s.require_path = "lib"
#  s.autorequire = "name"
  s.test_files = FileList["{test}/**/*test.rb"].to_a
  s.has_rdoc = true
  s.extra_rdoc_files = ["README"]
  s.add_dependency("nokogiri", ">=1.4.1")
end
 
Rake::GemPackageTask.new(spec) do |pkg| 
  pkg.need_tar = true 
end 

