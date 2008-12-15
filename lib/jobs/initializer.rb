require 'yaml'
require 'active_record'

module Jobs
  class Initializer
    def self.run!(job_root_path,job_config_path,env)
      ::ActiveRecord::Base.send(:include,Jobs::Scheduler)
      # define the Jobs::Config constant, e.g. RAILS_ROOT/config/jobs.yml
      eval %{::Jobs::Config=HashWithIndifferentAccess.new(YAML.load_file(job_config_path)[env])}
      # define the jobs root e.g. RAILS_ROOT/apps/jobs
      eval %{::Jobs::Root=job_root_path}
    end

    def self.ready?
      defined?(::Jobs::Root) and defined?(::Jobs::Config)
    end

    def self.rails!
      run! "#{RAILS_ROOT}/app/jobs", "#{RAILS_ROOT}/config/jobs.yml", RAILS_ENV
    end

    def self.test!
      run! File.join(File.dirname(__FILE__),'..','..','tests','jobs'), File.join(File.dirname(__FILE__),'..','..','config','jobs.yml'), 'test'
    end
  end
end
