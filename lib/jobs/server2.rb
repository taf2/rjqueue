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

    def run(foreground=true)
      @foreground = foreground
      if @foreground
        startup
        run_loop
      else
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
        exit(1) if output.match(/ERROR/i)
      end
    end

    private

    def run_loop
      
      @config['workers'].times { start_worker }

      @sleep_time = @min_wait_time

      begin
        while(@running) do
          count = 0
          begin
            if IO.select([@sock],[],[],@sleep_time)
              while( (msg = @sock.read_nonblock(1)) ) do # each message is 1 byte ['s','t']
                count += 1 # a new message, increment the request count
              end
            else
              count += 1 # timeout, tell the worker process to check again
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
          worker = Jobs::Worker.new(config,config_path,logger,env)
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
      count.times do
        Process.kill( 'USR1', @workers[@next_worker] )
        @next_worker += 1 # simple round robin...
        @next_worker = 0 if @next_worker >= @workers.size
      end
    end

    def startup
      enable_logger

      unless defined?(Jobs::Initializer) and Jobs::Initializer.ready?
        require 'rubygems'
        require 'jobs/client'
        Jobs::Initializer.run! File.join(@runpath,@config['jobpath']), @config_path, @env
      end

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

  end

end
