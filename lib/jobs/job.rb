module Jobs
  class Job < ActiveRecord::Base
    serialize :data
    belongs_to :taskable, :polymorphic => true

    #
    # check if the job is currently being processed
    #
    # e.g. status == 'processing' or status == 'pending'
    #
    def busy?
      self.status != 'processing' and self.status != 'pending'
    end

    def instance(logger_instance, lock)
      load("#{Jobs::Root}/#{name}_job.rb")
      klass = "#{name}_job".camelize.constantize
      klass.new(self,logger_instance, lock)
    rescue Object => e
      logger.error "#{e.message}\n#{e.backtrace.join("\n")}"
      return nil
    end
    
    def retry
      return false if locked
      self.status = 'pending'
      signal
      save
    end

    LockedError = Class.new(::StandardError)

    def retry!
      raise LockedError if locked
      self.status = 'pending'
      signal
      save!
    end
  end
end
