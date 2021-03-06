#
# Worker Process
# 
# Loads whatever environment you need running to manage and run jobs.
#
# A master process listens for UDP Packets and then delegates to a worker process
# The master keep track of how busy the worker processes are.
#
# Besides monitoring the child processes are forked by the master process. The master process
# can then use signals to trigger the worker to check for new work.
#
#
# pid = fork do
#   worker = Worker.new(config,logger)
#   signal our parent to let it know we're up and running
#   worker.listen # waits for SIGUSR1 to check for work, and SIGUSR2 to exit
# end
#
# wait for child to signal us with it's startup status
#
# workers << pid
#

require 'thread'
require 'rubygems'
require 'mysql'
require 'active_record'
require 'jobs/client'
require 'jobs/runnable'

module Jobs
  class Worker
    include Jobs::Runnable
    def initialize(config, runpath, config_path, logger, env)
      @config = config
      @runpath = runpath
      @config_path = config_path
      @logger = logger
      @queue = Queue.new
      @lock = Mutex.new
      @sig_lock = Mutex.new
      @thread = nil
      @env = env
      preload

      unless defined?(Jobs::Initializer) and Jobs::Initializer.ready?
        Jobs::Initializer.run! File.join(@runpath,@config['jobpath']), @config_path, @env
      end

      establish_connection
      @threads = (@config['threads'] or 1).to_i
      @pid = Process.pid
    end

    def listen
      @alive = true
      @thread = Thread.new{ worker }
      @count = 0
      trap("USR1") { @sig_lock.synchronize {@count += 1} } # queue up some work 
      trap("USR2") { @alive = false; trap("USR2",'SIG_DFL'); @logger.debug("USR2: shutdown")   } # sent to stop normally
      trap('TERM') { @alive = false; trap("TERM",'SIG_DFL'); @logger.debug("TERM: shutdown")  }
      trap('INT')  {  @alive = false; trap("INT",'SIG_DFL'); @logger.debug("INT: shutdown") }

      while @alive do
        sleep 1 # 1 second resolution
        count = 0
        @sig_lock.synchronize{ count = @count; @count = 0 }
        if count > 0
          @logger.debug("[job worker #{@pid}]: processing #{count} jobs")
          @queue.push count
        end
      end
      @queue.push nil
      @logger.info "[job worker #{@pid}]: Joining with main thread"
      @thread.join # wait for the worker
    end

  private
    def worker
      while @alive
        count = 0

        @logger.debug "[job worker #{@pid}]: #{Process.pid} waiting..."
        count = @queue.pop # sleep until we get some work
        @logger.debug "[job worker #{@pid}]: #{@pid} awake with: #{count} suggested jobs"

        break if count.nil? # if we get a nil count we're done

        count = @threads if count == 0

        jobs = []

        begin
          Jobs::Job.transaction do

            conditions = sql_runnable_conditions(@config['jobs_included'], @config['jobs_excluded'])
            jobs = Jobs::Job.find(:all, :conditions => conditions, :limit => count ) # only retrieve as many jobs as we were told about

            # lock the jobs we're about to process here
            @logger.debug "[job worker #{@pid}]: got #{jobs.size} to process out of #{count}"
            jobs.each do|job|
              job.locked = true
              job.save!
            end
          end

          reload!

          if jobs.size > 2 and @threads > 1
            threads = jobs.map do |job|
              Thread.new(job) do|j|
                process(j)
              end
            end
            threads.each{ |t| t.join }
          else
            jobs.each do |job|
              process(job)
              break unless @alive
            end
          end
        ensure
          Jobs::Job.transaction do
            jobs.each do|job|
              if job.locked
                job.locked = false
                job.save!
              end
            end
          end
        end

      end
      @logger.info "[job worker #{@pid}]: exiting work thread"
    end

    def process(job)
      job.status = 'processing'
      job.save!
      task = job.instance(@logger, @lock)
      if task
        task.real_execute
      else
        # report no job defined error
      end
    rescue Object => e
      @logger.error "[job worker #{@pid}]: #{e.message}\n#{e.backtrace.join("\n")}"
      if job
        job.details ||= ""
        job.details << "#{e.message}\n#{e.backtrace.join("\n")}"
        job.status = 'error'
      end
    end

    def preload
      if @config['preload']
        preload = @config['preload']
        if preload.is_a?(Array)
          preload.each { |f| require f }
        else
          require preload
        end
      end
    end

    def establish_connection

      @logger.info("[job worker #{@pid}]: establish connection environment with #{@config_path.inspect} and env: #{@env.inspect}")
      @db = YAML.load_file(File.join(File.dirname(@config_path),'database.yml'))[@env]
      ActiveRecord::Base.establish_connection @db
      #ActiveRecord::Base.logger = @logger

      # load the jobs/job model
      require 'jobs/job'
    end

    def reload!
      if defined?(RAILS_ENV) and RAILS_ENV != 'production'
        # if this method is defined, it'll be called before each job is executed... during
        # development this allows you to change your job code without restarting the job server...
        # clear things out

        ActiveRecord::Base.reset_subclasses if defined?(ActiveRecord)
        ActiveSupport::Dependencies.clear if defined?(ActiveSupport)
        ActiveRecord::Base.clear_reloadable_connections! if defined?(ActiveRecord)
        
        # reload the environment... XXX: skipping the run_callbacks from reload_application in dispatcher.rb action_pack...
        # this might cause the shit to hit the fan...
        Routing::Routes.reload if defined?(Routing)
        ActionController::Base.view_paths.reload! if defined?(ActionController)
        ActionView::Helpers::AssetTagHelper::AssetTag::Cache.clear if defined?(ActionView)
      end
    end

  end
end
