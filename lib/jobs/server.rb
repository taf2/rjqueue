# Jobs server
#
# Listens for UDP packets, signaling work to be processed
#
# If no messages are received, the server will poll for new jobs, faster or slower
# depending on the volume of work (jobs).  If the server wakes up after a timeout
# only to find no jobs to process, it will double its timeout until either jobs are found
# or it reaches a max configurable timeout.  The server both polls for work and listens for 
# work events.  The main reason is the work event is designed to be a nudge for the server. If
# the server is busy the nudge will be ignored.  Otherwise the work that needs to be processed, is
# always in the database, so regardless of the udp packets the server will get to each job.  The
# messages carry with them no work related information, they simply tell the server to check for work
# sooner then it would otherwise. Work is processed concurrently (as much as ruby will permit), which in the 
# case of spawning processes is relatively high.   
#


require 'socket'

module Jobs

class Server

  def initialize(run_path, config_path, env)
    @config_path = File.expand_path(config_path)
    @runpath = run_path
    @env = env
  end

  def log(msg, level=:info)
    @logger.send(level,msg)
  end

  # prepare the process to run independent of it's execution startup environment
  def enable_daemon
    Process.setsid
    File.open(@pid_file, 'wb') {|f| f << Process.pid}
    Dir.chdir('/')
    File.umask 0000
    STDIN.reopen "/dev/null"
    STDOUT.reopen "/dev/null", "a"
    STDERR.reopen STDOUT

    trap_exit
  end

  def trap_exit
    trap("TERM") { puts "trap TERM"; shutdown(1) }
    trap("INT") { puts "trap INT"; shutdown(1) }
    trap("HUP") { puts "trap HUP" }
    at_exit { puts "at_exit"; shutdown(nil) }
  end

  # load the server configuration, and intialize configuration instance variables
  def load_config
    require 'yaml'
    @config = YAML.load_file(@config_path)
    @config = @config[@env]
    if @config['runpath']
      runpath = @config['runpath']
      if !runpath.match(/^\//)
        @runpath = File.expand_path(runpath)
      else
        @runpath = runpath
      end
    end
 
    @pid_file = @config['pidfile'] or File.join(@runpath,'log','jobs.pid')

    if !@pid_file.match(/^\//)
      # make pidfile path absolute
      @pid_file = File.join(@runpath,File.dirname(@pid_file), File.basename(@pid_file))
    end

    # store some common config keys
    @min_wait_time = @config['min_wait_time'] || 10
    @max_wait_time = @config['max_wait_time'] || 60
    @port          = @config['port'] || 4321
    @host          = @config['host'] || '127.0.0.1'
    @process       = @config['process'] || 10
  end

  # setup logging
  def enable_logger
    require 'logger'
    if @config['logfile']
      @logfile = @config['logfile']
      if @foreground
        @logger = Logger.new(STDOUT)
      else
        if !@logfile.match(/^\//)
          @logfile = File.join(@runpath, @logfile)
        end
        @logger = Logger.new( @logfile )
      end
    else
      @logger = Logger.new( '/dev/null' )
    end
  end

  def setup_privileges
    require 'etc'

    user = @config['user']
    group = @config['group']
    change_privilege(user,group) if user and group
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
    require 'rubygems'
    require 'active_record'

    if @config['establish_connection']
      require 'mysqlplus'
      ::Mysql.class_eval { alias :query :async_query }
      @logger.info("establish connection environment with #{@config_path.inspect} and env: #{@env.inspect}")
      @db = YAML.load_file(File.join(File.dirname(@config_path),'database.yml'))[@env]
      ActiveRecord::Base.establish_connection @db
      ActiveRecord::Base.logger = @logger
      #ActiveRecord::Base.logger = Logger.new( "#{@logfile}-db.log" )
    end
    # now load the jobs/job model
    require 'jobs/job'
  end

  def migrate
    load_config
    enable_logger
    preload
    establish_connection
    require 'jobs/migrate'
    CreateJobs.up
  end

  def kill
    load_config
    system("kill #{File.read(@pid_file)}")
  end

  def run_foreground
    @foreground = true
    load_config
    # XXX: change back to the runpath... this means if the runpath is removed
    # say by a cap deploy... the daemon will likely die. 
    Dir.chdir(@runpath)

    # process is now a daemon
    enable_logger
    preload
    establish_connection
    trap_exit

    unless Jobs::Initializer.ready?
      require 'jobs/client'
      Jobs::Initializer.run! File.join(@runpath,@config['jobpath']), @config_path, @env
    end

    # open sock connection 
    sock = bind_sock

    @logger.info "Job process active"
    # enable the job queue and run the job loop
    @running = true

    checkjobs(sock)
  end

  def run_daemonized
    load_config
    puts "Starting job queue"
    if File.exist?(@pid_file)
      STDERR.puts "Pid file for job already exists: #{@pid_file}"
      exit 1
    end
    # daemonize, create a pipe to send status to the parent process, after the child has successfully started or failed
    rd, wr = IO.pipe
    # wait for child process to start running before exiting parent process
    fork do
      rd.close
      Process.setsid
      fork do
        begin
          enable_daemon

          # XXX: change back to the runpath... this means if the runpath is removed
          # say by a cap deploy... the daemon will likely die. 
          Dir.chdir(@runpath)

          # process is now a daemon
          enable_logger
          setup_privileges
          preload
          establish_connection
 
          require 'jobs/client'
          unless Jobs::Initializer.ready?
            Jobs::Initializer.run! File.join(@runpath,@config['jobpath']), @config_path, @env
          end

          # open sock connection 
          sock = bind_sock

          @logger.info "Job process active"

          wr.write "Listening on udp://#{@host}:#{@port}\n"
          wr.flush
          wr.close # signal to our parent we're up and running, this lets the parent exit

          # enable the job queue and run the job loop
          @running = true
          checkjobs(sock)
        rescue Object => e
          if wr.closed?
            @logger.error "#{e.message} #{e.backtrace.join("\n")}"
          else
            wr.write e.message
            wr.write e.backtrace.join("\n")
            wr.write "\n"
            wr.write "ERROR!"
            wr.flush
            wr.close
            exit(1)
          end
        ensure
          # if for whatever reason the child exits, shutdown to clean up pid file, etc...
          shutdown(1)
        end
      end
      wr.close
    end
    wr.close
    output = rd.read
    puts output
    rd.close
    if output.match(/ERROR/i)
      exit(1)
    else
      exit(0)
    end
  end

  # Change privileges of the process to specified user and group. (original source mongrel)
  def change_privilege(user, group)
    uid, gid = Process.euid, Process.egid
    target_uid = Etc.getpwnam(user).uid if user
    target_gid = Etc.getgrnam(group).gid if group

    if uid != target_uid or gid != target_gid
      @logger.info "[jobqueue] Initiating groups for #{user.inspect}:#{group.inspect}."
      Process.initgroups(user, target_gid)

      @logger.info "[jobqueue] Changing group to #{group.inspect}."
      Process::GID.change_privilege(target_gid)

      @logger.info "[jobqueue] Changing user to #{user.inspect}."
      Process::UID.change_privilege(target_uid)
    end
  rescue Errno::EPERM => e
    @logger.error "[jobqueue] Couldn't change user and group to #{user.inspect}:#{group.inspect}: #{e.to_s}."
    @logger.error "[jobqueue] failed to start."
    exit 1
  end

  # shutdown, typically called from a signal handler
  def shutdown(ret=0)
    @logger.info "[jobqueue] Stopping: #{@pid_file.inspect}"
    @running = false # make sure the job queue doesn't continue, if for example unlink fails
    if File.exist?(@pid_file)
      File.unlink(@pid_file)
    end
    exit(ret) if !ret.nil? # exit with status 0 to indicate we exited properly
  end

  #
  # Monitors the job queue.
  #   polls the database for new jobs
  #   spawns @process number of threads to handle new job requests,
  #   this value should be equal to the number of connections to the database
  #
  def work_thread
    # process @process jobs at at time and sleep for 10 seconds
    while(@running) do
      count = 0
      if @queue.empty?
      count = @queue.pop
      else
        begin
          # pop as many off the queue as we can until an exception is raised because the queue is
          # empty, or until we reach @process number of jobs
          count += @queue.pop(true) until count >= @process
        rescue ThreadError => e # when the queue is empty it'll raise an exception
        end
      end
      @logger.debug "[jobqueue] awake after #{@sleep_time} seconds, queued: #{@queue.size}"
      jobs = []

      # we were awoken, start processing jobs
      while(@running) do
        timer = Time.now
        @logger.debug "\n[jobqueue] checking for new jobs..."

        # update in the transaction each job's status and lock attribute
        # this is critical, to avoid multiple job queue processes from picking up the same @process job records
        @lock.synchronize do

          Jobs::Job.transaction do
            jobs = Jobs::Job.find(:all, :conditions => {:status => 'pending', :locked => false}, :limit => @process)
            jobs.each do|job|
              job.locked = true
              job.status = 'processing'
              job.save
            end
          end

        end

        @logger.debug "[jobqueue] processing: #{jobs.size}, with #{@queue.size} queued after #{Time.now - timer}"
        timer = Time.now
        # check if we got any jobs
        if jobs.empty?
          # when no jobs were found, sleep longer the next time
          @lock.synchronize {
            @sleep_time *= 2
            @sleep_time = @max_wait_time if @sleep_time > @max_wait_time # max
          }
          break
        else
          @lock.synchronize {
            @sleep_time /= 2
            @sleep_time = @min_wait_time if @sleep_time < @min_wait_time # min
          }
        end

        if jobs.size < 2
          # spawn a thread for each job
          threads = jobs.map do |j|
            Thread.new(j) do |job|
              begin
                # get a single connection per job thread
                task = @lock.synchronize { job.instance(@logger, @job_lock) } # lock while loading the job
                task.real_execute
                @logger.debug "[jobqueue] job complete"
              rescue Object => e
                @logger.error "#{e.message} #{e.backtrace.join("\n")}"
                # this most likely means we never got to real_execute, so syntax error...
                job.status = "error"
                job.save
              end
            end
          end

          # wait for all the jobs to finish
          threads.each {|t| t.join }
        else
          jobs.each do|job|
            begin
              # get a single connection per job thread
              task = @lock.synchronize { job.instance(@logger, @job_lock) } # lock while loading the job
              task.real_execute
              @logger.debug "[jobqueue] job complete"
            rescue Object => e
              @logger.error "#{e.message} #{e.backtrace.join("\n")}"
              # this most likely means we never got to real_execute, so syntax error...
              job.status = "error"
              job.save
            end
          end
        end

        @logger.debug "[jobqueue] finished processing: #{jobs.size}, after #{Time.now - timer}. waiting 0.1 seconds..."
        sleep 0.1 # avoid spiking cpu in event we can never finish a job
      end
    end
  rescue Object => e
    @logger.error "[jobqueue] #{e.message}\n#{e.backtrace.join("\n")}"
    retry
  end

  def bind_sock
    # listen to udp packets
    sock = UDPSocket.open
    sock.bind(@host, @port)
    sock
  end

  #
  # Main thread, opens a UDP socket to monitor job requests
  # starts up the worker_thread
  # Uses a Queue @queue to communicate to the worker_thread, passing the number of new job requests to the thread
  #
  def checkjobs(sock)
    @sleep_time = @min_wait_time

    @queue = Queue.new
    @lock = Mutex.new # create a lock to syncrhonize data passed between the worker_thead and the main thread
    @job_lock = Mutex.new # this lock is available to jobs that need to syncrhonize...

    Thread::abort_on_exception=false

    # start up the work thread
    worker = Thread.new{ work_thread }

    
    @queue.push 1 # push one to get thing started, trigger work_thread to check for jobs pending

    begin
      while(@running) do
        count = 0
        begin
          st = @lock.synchronize{ @sleep_time }
          if IO.select([sock],[],[],st)
            while( (msg = sock.read_nonblock(5)) ) do # each message is 5 bytes
              count += 1 # a new message, increment the request count
            end
          else
            count += 1 # timeout, tell the worker thread to check again
          end
        rescue Errno::EAGAIN => e
          # there is more information pending, but we don't have it hear yet... not sure if this condition happens with UDP
        end

        if count > 0 #and @queue.size < 5 # no reason to flood this queue, if we have that much work... we need more processes
          @logger.info("[jobqueue]: new work events received: #{count}")
          @queue.push count
        end

      end
    rescue Object => e
      @logger.error "[jobqueue] #{e.message}\n#{e.backtrace.join("\n")}"
      retry
    end
    worker.kill
  end

end # end Runner

end # end Jobs
