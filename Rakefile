require 'rake'
require 'rake/testtask'

RJQ_VERSION="0.2.2"

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
    puts "manually kill. e.g. 'kill `cat tests/logs/jobqueue.pid`" if File.exist?("tests/logs/jobqueue.pid")
    exit(status.exitstatus)
  end

  # run tests
  system("ruby -I tests -I tests/lib tests/test_server.rb")

  # stop the job queue
  system("kill #{File.read('tests/logs/jobqueue.pid')}")

end

task :default => :test

desc 'Generate gem specification'
task :gemspec do
  require 'erb'
  tspec = ERB.new(File.read(File.join(File.dirname(__FILE__),'lib','rjqueue.gemspec.erb')))
  File.open(File.join(File.dirname(__FILE__),'rjqueue.gemspec'),'wb') do|f|
    f << tspec.result
  end
end

desc 'Build gem'
task :build => :gemspec do
  require 'rubygems/specification'
  spec_source = File.read File.join(File.dirname(__FILE__),'rjqueue.gemspec')
  spec = nil
  # see: http://gist.github.com/16215
  Thread.new { spec = eval "$SAFE = 3\n#{spec_source}" }.join
  spec.validate
  Gem::Builder.new(spec).build
end

desc 'Install the gem'
task :install  => :build do
  if RUBY_PLATFORM.match(/mswin32/)
    system("gem install rjqueue-#{RJQ_VERSION}")
  else
    system("sudo gem install rjqueue-#{RJQ_VERSION}")
  end
end
