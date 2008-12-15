
class SimpleJob < Jobs::Base
  def execute
    sleep 1 # one second
  end
end
