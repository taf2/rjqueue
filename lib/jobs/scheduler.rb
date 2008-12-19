require 'socket'
require 'yaml'
require 'active_record'
require 'jobs/job'
require 'jobs/config'

module Jobs

  module Scheduler
    def schedule(job_name, options={})
      threadable = options.delete(:threadable)
      
      job = Jobs::Job.new(:name          => job_name.to_s.strip,
                          :data          => options,
                          :taskable_id   => self.id,
                          :taskable_type => self.class.to_s,
                          :status        => "pending")
      job.save!

      signal(job_name,threadable)

      job.id
    end

    #
    # send a signal to wake job queue
    #
    # threadable: provides a hint that a threaded worker may be used to run the job
    #
    def signal(job_name=nil,threadable=nil)
      socket = UDPSocket.open
      #socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
      hosts = ::Jobs::Config.host_for_job(job_name)
      if hosts.is_a?(Array)
      else
        socket.send(threadable ? 't' : 's', 0, hosts[:host], hosts[:port] )
      end
    end
  end

end
