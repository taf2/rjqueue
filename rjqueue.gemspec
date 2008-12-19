Gem::Specification.new do |s|
  s.name = 'rjqueue'
  s.version = '0.1.4'
  s.summary = "Ruby Job Queue"
  s.description = <<-EOF
    A Job Queue Server.  Responses to UDP requests.
  EOF

  

  s.files = ["LICENSE", "README", "Rakefile", "bin/rjqueue", "config/database.yml", "config/jobs.yml", "lib/jobs/scheduler.rb", "lib/jobs/initializer.rb", "lib/jobs/config.rb", "lib/jobs/migrate.rb", "lib/jobs/worker.rb", "lib/jobs/runnable.rb", "lib/jobs/job.rb", "lib/jobs/server.rb", "lib/jobs/client.rb", "lib/jobs/base.rb"]

  #### Load-time details
  s.require_path = 'lib'

  #### Documentation and testing.
  s.has_rdoc = true

  s.platform = Gem::Platform::RUBY

  
  s.test_files = ["tests/sample.png", "tests/test_server.rb", "tests/jobs/simple_job.rb", "tests/jobs/image_thumb_job.rb", "tests/jobs/find_file_job.rb", "tests/lib/message.rb", "tests/lib/image.rb", "tests/lib/create_test_data.rb"]

  #### Author and project details.

  s.author = "Todd A. Fisher"
  s.email = "todd.fisher@gmail.com"
  s.homepage = "http://idle-hacking.com/"
  s.rubyforge_project = "rjqueue"
  s.bindir = "bin"
  s.executables = ["rjqueue"]
end
