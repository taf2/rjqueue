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

module Jobs
  class Worker
    def initialize(config, config_path, logger, env)
      @config = config
      @config_path = config_path
      @logger = logger
      @queue = Queue.new
      @lock = Mutex.new
      @sig_lock = Mutex.new
      @thread = nil
      @env = env
      preload
      establish_connection
      @process = @config['process']
      @pid = Process.pid
    end

    def listen
      @alive = true
      @thread = Thread.new{ worker }
      @count = 0
      trap("USR1") { @logger.debug("[job worker #{@pid}]: queue event #{@count}"); @sig_lock.synchronize {@count += 1} } # queue up some work 
      trap("USR2") { @alive = false; trap("USR2",'SIG_DFL') } # sent to stop normally
      trap('TERM') { @alive = false; trap("TERM",'SIG_DFL') }
      trap('INT')  { @alive = false; trap("INT",'SIG_DFL') }

      while @alive do
        sleep 1 # 1 second resolution
        count = 0
        @sig_lock.synchronize{ count = @count; @count = 0 }
        if count > 0
          @logger.debug("[job worker #{@pid}]: processing #{count} jobs")
          if count > @process # we've queued up more then we can handle chunk it out and start chugging away
            (count/@process).times do
              a = count - (count-@process)
              @logger.debug("[job worker #{@pid}]: queueing #{a}")
              @queue << a
              count = (count-@process)
            end
            if count > 0
              @logger.debug("[job worker #{@pid}]: queueing #{count}")
              @queue << count
            end
          else
            @logger.debug("[job worker #{@pid}]: queueing #{count}")
            @queue << count
          end
        end
      end
      @queue << nil
      @logger.info "[job worker #{@pid}]: Joining with main thread"
      @thread.join # wait for the worker
    end

  private
    def worker
      while @alive
        count = 0

        if @queue.empty?
          @logger.debug "[job worker #{@pid}]: #{Process.pid} waiting..."
          count = @queue.pop # sleep until we get some work
        else
          begin # pop as many as we can until we reach a max
            while count < @config['process'] do
              value = @queue.pop(true)
              if value.nil?
                count = nil
                break
              end
              count += value
            end
          rescue ThreadError => e
          end
        end

        @logger.debug "[job worker #{@pid}]: #{Process.pid} awake with: #{count} suggested jobs"

        break if count.nil? # if we get a nil count we're done

        count = @process if count == 0

        jobs = []

        begin
          Jobs::Job.transaction do
            jobs = Jobs::Job.find(:all, :conditions => {:status => 'pending', # only if the job is pending
                                                        :locked => false}, # only if the job is not locked
                                        :limit => count ) # only retrieve as many jobs as we were told about
            # lock the jobs we're about to process here
            @logger.debug "[job worker #{@pid}]: got #{jobs.size} to process out of #{count}"
            jobs.each do|job|
              job.locked = true
              job.save!
            end
          end

          if jobs.size > 2 and @config['enable_threads']
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
      #ActiveRecord::Base.logger = Logger.new( "#{@logfile}-db.log" )
      ActiveRecord::Base.logger = Logger.new( "/dev/null" )

      # load the jobs/job model
      require 'jobs/job'
    end
  end
end
