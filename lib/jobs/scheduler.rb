require 'socket'
require 'yaml'
require 'active_record'
require 'jobs/job'

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

      signal(threadable)

      job.id
    end

    #
    # send a signal to wake job queue
    #
    # threadable: provides a hint that a threaded worker may be used to run the job
    #
    def signal(threadable=nil)
      socket = UDPSocket.open
      #socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)

      socket.send(threadable ? 't' : 's', 0, ::Jobs::Config[:host], ::Jobs::Config[:port] )
    end
  end

end
