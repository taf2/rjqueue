require 'socket'
require 'yaml'
require 'active_record'
require 'jobs/job'

module Jobs

  module Scheduler
    def schedule(job_name, options={})
      job = Jobs::Job.new(:name          => job_name.to_s.strip,
                          :data          => options,
                          :taskable_id   => self.id,
                          :taskable_type => self.class.to_s,
                          :status        => "pending")
      job.save!

      signal

      job.id
    end

    def signal
      socket = UDPSocket.open
      #socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
      socket.send("wake", 0, ::Jobs::Config[:host], ::Jobs::Config[:port] )
    end
  end

end
