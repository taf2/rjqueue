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
      if RAILS_ENV != 'production'
        # if this method is defined, it'll be called before each job is executed... during
        # development this allows you to change your job code without restarting the job server...
        Jobs::Server.class_eval do
          def reload!
            # clear things out
            ActiveRecord::Base.reset_subclasses if defined?(ActiveRecord)
            ActiveSupport::Dependencies.clear
            ActiveRecord::Base.clear_reloadable_connections! if defined?(ActiveRecord)
            
            # reload the environment... XXX: skipping the run_callbacks from reload_application in dispatcher.rb action_pack...
            # this might cause the shit to hit the fan...
            Routing::Routes.reload
            ActionController::Base.view_paths.reload!
            ActionView::Helpers::AssetTagHelper::AssetTag::Cache.clear
          end
        end
      end
    end

    def self.test!
      run! File.join(File.dirname(__FILE__),'..','..','tests','jobs'), File.join(File.dirname(__FILE__),'..','..','config','jobs.yml'), 'test'
    end
  end
end
