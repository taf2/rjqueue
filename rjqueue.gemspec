Gem::Specification.new do |s|
  s.name = 'rjqueue'
  s.version = "0.1.0"
  s.summary = "Ruby Job Queue"
  s.description = <<-EOF
    A Job Queue Server.  Responses to UDP requests.
  EOF

  s.files = ["LICENSE", "README", "Rakefile",
           "bin/rjqueue", "config/database.yml",
           "config/jobs.yml"] + Dir["lib/**/**.rb"]

  #### Load-time details
  s.require_path = 'lib'

  #### Documentation and testing.
  s.has_rdoc = true

  s.platform = Gem::Platform::RUBY

  s.test_files = ["tests/sample.png"] + Dir["test/**/**.rb"]

  #### Author and project details.

  s.author = "Todd A. Fisher"
  s.email = "todd.fisher@gmail.com"
  s.homepage = "http://idle-hacking.com/"
  s.rubyforge_project = "rjqueue"
  s.bindir = "bin"
  s.executables = ["rjqueue"]
end
