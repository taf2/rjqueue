require 'pathname'

module Jobs
  class Config

    def self.host_for_job(name)
      if defined?(::Jobs::HostMap) and ::Jobs::HostMap.key?(name)
        ::Jobs::HostMap[name]
      else
        {:host => ::Jobs::Keys[:host], :port => ::Jobs::Keys[:port]}
      end
    end

    def self.jobpath
      rp = Pathname.new(Jobs::Keys['runpath'])
      jp = Pathname.new(Jobs::Keys['jobpath'])
      if jp.relative?
        (rp + jp).to_s
      else
        jp.to_s
      end
    end

  end
end
