require 'rake'
require 'rake/testtask'
begin
  require 'rake/gempackagetask'
rescue LoadError
  $stderr.puts("Rubygems support disabled")
end


desc 'Set up environment, setup database options in config/database.yml'
task :setup do
  require 'active_record'
  db = YAML.load_file(File.join(File.dirname(__FILE__),'config','database.yml'))[(ENV['DB']||'development')]
  ActiveRecord::Base.establish_connection db
  $:.unshift File.join(File.dirname(__FILE__),'lib')
  require 'jobs/migrate'
  CreateJobs.up
end

desc 'Set up test database'
task :test_prepare do
  require 'active_record'
  db = YAML.load_file(File.join(File.dirname(__FILE__),'config','database.yml'))[(ENV['DB']||'test')]
  ActiveRecord::Base.establish_connection db
  $:.unshift File.join(File.dirname(__FILE__),'lib')
  require 'jobs/migrate'
  CreateJobs.up
  $:.unshift File.join(File.dirname(__FILE__),'tests','lib')
  require 'create_test_data'
  CreateTestData.up
end

desc 'Run tests'
task :test => :test_prepare do
  # start up the server
  lib_path = File.expand_path("./lib")
  pid = fork { exec "ruby -I '#{lib_path}' ./bin/rjqueue -d --config config/jobs.yml --environment test" }

  p, status = Process.wait2(pid)

  if status.exitstatus != 0
    puts "Failed to start server"
    puts "manually kill. e.g. 'kill `cat tests/logs/jobqueue-4321.pid`" if File.exist?("tests/logs/jobqueue-4321.pid")
    exit(status.exitstatus)
  end

  # run tests
  system("ruby -I tests -I tests/lib tests/test_server.rb")

  # stop the job queue
  system("kill #{File.read('tests/logs/jobqueue-4321.pid')}")

end

task :default => :test

if ! defined?(Gem)
  warn "Package Target requires RubyGEMs"
else
  spec = Gem::Specification.new do |s|

    #### Basic information.

    s.name = 'rjqueue'
    s.version = "0.1.0"
    s.summary = "Ruby Job Queue"
    s.description = <<-EOF
      A Job Queue Server.  Responses to UDP requests.
    EOF

    #### Which files are to be included in this gem?

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

  package_task = Rake::GemPackageTask.new(spec) do |pkg|
    pkg.need_zip = true
    pkg.need_tar_gz = true
    pkg.package_dir = 'pkg'
  end
end

desc 'Install the gem'
task :install  => :package do
  #TODO handle sudo for windows
  system("sudo gem install pkg/")
end


