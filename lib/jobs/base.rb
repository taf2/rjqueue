module Jobs
  class Base
    attr_reader :record, :logger, :lock

    def initialize(job_record, logger, lock)
      @record = job_record
      @logger = logger
      @lock = lock
    end

    def execute
    end

    # really run the execute method
    def real_execute
      timer = Time.now

      res = execute

      @record.duration = Time.now - timer

      @record.status = res ? "complete" : "error"

    rescue Object => e
      # add error details to the record
      @record.details ||= ""
      @record.details << "#{e.message}\n#{e.backtrace.join("\n")}"

      # log the error
      @logger.error "#{e.message}\n#{e.backtrace.join("\n")}"
      @record.status = "error"
    ensure
      # it's no longer processing, so we must have landed here by error
      @record.status = 'error' if @record.status == 'processing'
      @record.locked = false
      @record.save
    end

    protected

    #
    # call a process: capture the command output and status code
    # returns [status, output]
    def call(cmd)
      rd, wr = IO.pipe
      pid = fork do
        $stdout.reopen wr
        $stderr.reopen wr
        $stdin.reopen rd
        exec cmd
      end
      wr.close
      pid, status = Process.wait2(pid)
      [status, rd.read]
    end

  end
end
