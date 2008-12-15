

pid = fork do
  require 'yaml'
  require 'rubygems'
  require 'mysql'
  require 'active_record'

  db = YAML.load_file(File.join(File.dirname(__FILE__),'config','database.yml'))['test']
  ActiveRecord::Base.establish_connection db

  $:.unshift File.join(File.dirname(__FILE__),'lib')
  require 'jobs/migrate'
  CreateJobs.up
  puts "migrated"
end

puts "waiting for migration"
Process.waitpid2(pid,0)

puts "starting seed process"

pid = fork do
  require 'yaml'
  require 'rubygems'
  require 'mysql'
  require 'active_record'

  db = YAML.load_file(File.join(File.dirname(__FILE__),'config','database.yml'))['test']
  ActiveRecord::Base.establish_connection db

  $:.unshift File.join(File.dirname(__FILE__),'lib')
  require 'jobs/job'
  require 'jobs/client'

  Jobs::Initializer.run!('test/jobs','config/jobs.yml','test')

  puts "seeding jobs"
  sleep 1 # pause
  # add jobs
  10.times { job = Jobs::Job.create(:name => 'simple', :data => {}, :status => "pending"); job.signal }
  sleep 1 # pause
  10.times { job = Jobs::Job.create(:name => 'simple', :data => {}, :status => "pending"); job.signal }

  puts "Jobs seeded"
end

puts "db ready starting server"

$:.unshift File.expand_path( File.join(File.dirname(__FILE__),'lib') )
require 'jobs/server'
Jobs::Server.new(".", "config/jobs.yml", "test").run(false)
Process.waitpid2(pid,0)
