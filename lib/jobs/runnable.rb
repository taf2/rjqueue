module Jobs
  module Runnable
    #
    # returns a sql query condition given the included and excluded 
    # jobs for the given process. e.g. jobs.name IN ('job1','job2') and jobs.name NOT IN ('jobs3','jobs5')
    # would allow only job1 and job2 to run on the server, but also deny jobs3 and jobs5
    # in this way the typical use would be to either use the deny or use the allow, but never both together...
    # however the following will handle both...
    #
    def sql_runnable_conditions(allowed,denied)
      conditions = "status='pending' and locked=0 "
      if allowed and !allowed.empty? and denied and !denied.empty? # both have something
        includes = allowed.map{|a| "'#{a}'" }.join(',')
        conditions << %Q( and name IN (#{includes}) )
        excludes = denied.map{|d| "'#{d}'" }.join(',')
        conditions << %Q( and name not IN (#{excludes}) )
      elsif allowed and !allowed.empty? and denied.nil? # only allowed
        includes = allowed.map{|a| "'#{a}'" }.join(',')
        conditions << %Q( and name IN (#{includes}) )
      elsif denied and !denied.empty? and allowed.nil? # only denied
        excludes = denied.map{|d| "'#{d}'" }.join(',')
        conditions << %Q( and name not IN (#{excludes}) )
      end
    end
  end
end
