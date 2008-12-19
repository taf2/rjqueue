require 'yaml'
require 'active_record'

module Jobs
  class Initializer
    def self.run!(job_root_path,job_config_path,env)
      ::ActiveRecord::Base.send(:include,Jobs::Scheduler)
      # define the Jobs::Keys constant, e.g. RAILS_ROOT/config/jobs.yml
      eval %{::Jobs::Keys=HashWithIndifferentAccess.new(YAML.load_file(job_config_path)[env])}
      # define the jobs root e.g. RAILS_ROOT/apps/jobs
      eval %{::Jobs::Root=job_root_path}
    end

    def self.ready?
      defined?(::Jobs::Root) and defined?(::Jobs::Keys)
    end

    def self.rails!
      run! "#{RAILS_ROOT}/app/jobs", "#{RAILS_ROOT}/config/jobs.yml", RAILS_ENV
    end

    # Configure client to be selective about which job servers to send work
    #
    # Jobs::Initializer.config do|cfg|
    #
    #  cfg[:sphinx] = [ {:host => '192.168.1.102', :port => 4321} ]
    #  cfg[:video_encoder] = [ {:host => '192.168.1.102', :port => 4321} ]
    #
    def self.config
      config = {}
      yield config
      eval %{::Jobs::HostMap=config}
    end

    def self.test!
      run! File.join(File.dirname(__FILE__),'..','..','tests','jobs'), File.join(File.dirname(__FILE__),'..','..','config','jobs.yml'), 'test'
    end
  end
end
