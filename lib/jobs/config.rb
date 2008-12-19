module Jobs
  class Config

    def self.host_for_job(name)
      if defined?(::Jobs::HostMap) and ::Jobs::HostMap.key?(name)
        ::Jobs::HostMap[name]
      else
        {:host => ::Jobs::Keys[:host], :port => ::Jobs::Keys[:port]}
      end
    end

  end
end
