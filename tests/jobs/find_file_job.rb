class FindFileJob < Jobs::Base
  # simple test to find a file

  def execute
    File.open("#{File.dirname(__FILE__)}/output", "w") do|f|
      f << call("find #{File.dirname(__FILE__)} -name find_file_job.rb").inspect
    end
  end

end
