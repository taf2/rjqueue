#
# Listen for UDP packets
#
# Start up X worker processes, communicates with worker processes by sending USR1 signal
# and USR2 to kill the process
#
require 'yaml'
require 'socket'

module Jobs

  class Server
    def initialize(runpath, config_path, env)
      @runpath = runpath
      @config_path = File.expand_path(config_path)
      @env = env
      @workers = []
      @next_worker = 0
      load_config
    end

    def run(daemonize=true)

      @daemonize = daemonize
      if @daemonize
        @child_up = false
 
        # use this to determine when all workers are started and the child process is ready to listen for events
        trap("USR1"){ @child_up = true }

        if File.exist?(@pid_file)
          STDERR.puts "Pid file for job already exists: #{@pid_file}"
          exit 1
        end
        # daemonize, create a pipe to send status to the parent process, after the child has successfully started or failed
        rd, wr = IO.pipe

        @parent_pid = Process.pid

        # wait for child process to start running before exiting parent process
        fork do
          rd.close
          Process.setsid
          fork do
            begin
              Process.setsid
              File.open(@pid_file, 'wb') {|f| f << Process.pid}
              Dir.chdir('/')
              File.umask 0000
              STDIN.reopen "/dev/null"
              STDOUT.reopen "/dev/null", "a"
              STDERR.reopen STDOUT

              # XXX: change back to the runpath... this means if the runpath is removed
              # say by a cap deploy... the daemon will likely die. 
              Dir.chdir(@runpath)

              startup

              @logger.info "Job process active"

              wr.write "Listening on udp://#{@host}:#{@port}\n"
              wr.flush
              wr.close # signal to our parent we're up and running, this lets the parent exit
              run_loop
            rescue => e
              if wr.closed?
                @logger.error "#{e.message} #{e.backtrace.join("\n")}"
              else
                wr.write e.message
                wr.write e.backtrace.join("\n")
                wr.write "\n"
                wr.write "ERROR!"
                wr.flush
                wr.close
              end
            ensure
              cleanup
            end
          end
          wr.close
        end
        wr.close
        output = rd.read
        puts output
        rd.close

        w = 0
        puts "Waiting for child workers to start..."
        while( !@child_up and w < 10 ) do
          sleep 1
          w+= 1
        end
        if @child_up
          puts "Workers up"
        else
          puts "Check error log, workers may not be started, or you may be starting so many workers it has taken longer then 10 seconds to start them all. In either event checking the log for details would be the first place to look."
        end

        exit(1) if output.match(/ERROR/i)
      else
        startup
        run_loop
      end
    end

    private

    def check_count
      count = 0
      res = @conn.query("select count(id) from jobs where status='pending' and locked=0")
      #count += 1 # timeout, tell the worker process to check again
      count = res.fetch_row[0].to_i
      #@logger.debug("[jobqueue]: #{count} ready")
      count
    rescue Mysql::Error => e
      @logger.error("[jobqueue]: #{e.message}\n#{e.backtrace.join("\n")}")
      count = 1
      db_connect!
      count
    ensure
      res.free if res
    end

    def db_connect!
      # connect to the MySQL server
      dbconf = YAML.load_file(File.join(File.dirname(@config_path),'database.yml'))[@env]
      @conn = Mysql.real_connect(dbconf['host'], dbconf['username'], dbconf['password'], dbconf['database'], (dbconf['port'] or 3306) )
    end

    def run_loop

      @sleep_time = @wait_time

      @config['workers'].times { start_worker }

      unless defined?(Jobs::Initializer) and Jobs::Initializer.ready?
        require 'rubygems'
        require 'jobs/client'
        Jobs::Initializer.run! File.join(@runpath,@config['jobpath']), @config_path, @env
      end

      # job queue master process needs to be aware of the number of jobs pending on timeout
      require 'rubygems'
      require 'mysql'

      db_connect!

      begin
        count = check_count
        signal_work(count)

        Process.kill("USR1", @parent_pid) if @parent_pid

        while(@running) do
          count = 0
          begin
            if IO.select([@sock],[],[],@sleep_time)
              while( (msg = @sock.read_nonblock(1)) ) do # each message is 1 byte ['s','t']
                count += 1 # a new message, increment the request count
              end
            else
              #@logger.debug("[jobqueue]: timeout")
              count = check_count
            end
          rescue Errno::EAGAIN => e
            # there is more information pending, but we don't have it hear yet... not sure if this condition happens with UDP
          end

          if count > 0 #and @queue.size < 5 # no reason to flood this queue, if we have that much work... we need more processes
            @logger.info("[jobqueue]: received #{count} events")
            # signal workers, distribute work load evenly to each worker
            signal_work(count)
          end

        end
      rescue Object => e
        if @running
          @logger.error "[jobqueue] #{e.message}\n#{e.backtrace.join("\n")}"
          retry
        end
      end

      @logger.info "Stopping workers"
      @workers.each do|worker|
        stop_worker(worker)
      end

    end

    def stop_worker(pid)
      @logger.info "Stopping worker: #{pid}"
      Process.kill('USR2', pid)
      Process.waitpid2(pid,0)
    end

    def start_worker
      config      = @config
      config_path = @config_path
      logger      = @logger
      env         = @env

      rd, wr = IO.pipe
      # startup workers
      @logger.info "starting worker"
      @workers << fork do
        begin
          rd.close
          require 'jobs/worker'
          worker = Jobs::Worker.new(config,@runpath, config_path,logger,env)
          @logger.info "created worker: #{Process.pid}"
          # signal parent
          wr.write "up"
          wr.close
          worker.listen
        rescue Object => e
          msg = "#{e.message}\n#{e.backtrace.join("\n")}"
          if wr.closed?
            @logger.error msg
          else
            wr.write msg
            wr.close
          end
        end
      end
      wr.close
      @logger.info "waiting for worker to reply"
      msg = rd.read
      rd.close
      @logger.info "worker: #{msg.inspect}"
      raise "Failed to start worker: #{msg.inspect}" if msg != 'up'
    end

    # tell a non-busy worker there is new work
    def signal_work(count) # count is unused
      return if count.nil? or count == 0
      count.times do
        Process.kill( 'USR1', @workers[@next_worker] )
        @next_worker += 1 # simple round robin...
        @next_worker = 0 if @next_worker >= @workers.size
      end
    end

    def startup
      enable_logger
 
      # open sock connection 
      @sock = bind_socket

      @logger.info "Job process active"
      @logger.info "Listening on udp://#{@host}:#{@port}\n"

      @running = true

      trap('TERM') { shutdown('TERM') }
      trap('INT') { shutdown('INT') }
      trap('HUP') { @logger.info 'ignore HUP' }
    end
 
    def shutdown(sig)
      @logger.info "trap #{sig}"
      @running = false # toggle the run state
      trap(sig,"SIG_DFL") # turn the signal handler off
      Process.kill("USR2", Process.pid) # resend the signal to trigger and exception in IO.select
    end

    def cleanup
      @logger.info "[jobqueue] Stopping: #{@pid_file.inspect}"
      if File.exist?(@pid_file)
        File.unlink(@pid_file)
      end
      @conn.close if @conn
    end

    def bind_socket
      # listen to udp packets
      sock = UDPSocket.open
      sock.bind(@host, @port)
      sock
    end

    # load the server configuration, and intialize configuration instance variables
    def load_config
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
      @wait_time     = @config['wait_time'] || 10
      @port          = @config['port'] || 4321
      @host          = @config['host'] || '127.0.0.1'
      @threads       = @config['threads'] || 10
    end

    # setup logging
    def enable_logger
      require 'logger'
      if @config['logfile']
        @logfile = @config['logfile']
        if @daemonize
          if !@logfile.match(/^\//)
            @logfile = File.join(@runpath, @logfile)
          end
          @logger = Logger.new( @logfile )
        else
          @logger = Logger.new(STDOUT)
        end
      else
        @logger = Logger.new( '/dev/null' )
      end
    end

  end

end
