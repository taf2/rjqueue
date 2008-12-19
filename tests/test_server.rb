require 'test/unit'
require 'rubygems'
require 'active_record'

# load the jobs client environment
$:.unshift File.join(File.dirname(__FILE__),'..','lib')
require 'jobs/client'

# load test models
$:.unshift File.join(File.dirname(__FILE__),'lib')
require 'message'
require 'image'

Jobs::Initializer.test!

class TestServer < Test::Unit::TestCase

  def setup
    # ensure we have a connection established
    if not ActiveRecord::Base.connected?
      ActiveRecord::Base.establish_connection YAML.load_file(File.join(File.dirname(__FILE__),'..','config','database.yml'))['test']
      ActiveRecord::Base.logger = Logger.new(File.join(File.dirname(__FILE__),'logs','test-db.log'))
    end
  end

  #
  # test running a background thumbnail creation job
  #
  def test_single_image_thumb_job
    timer = Time.now
    # create new message record
    image = Image.new :name => 'test',
                      :alt_text => 'sample',
                      :path => File.expand_path(File.join(File.dirname(__FILE__),'sample.png'))

    # save the new record, should trigger the image
    assert image.save

    wait_image_job_complete_or_error(image)

    dur = Time.now - timer
    puts "Duration: #{image.job.updated_at.to_f - image.job.created_at.to_f} seconds and duration: #{image.job.duration}, real: #{dur}"
  end

  def wait_image_job_complete_or_error(image)
    img = image
    until img.job.status != 'processing' and img.job.status != 'pending'
      puts "waiting on job with status: #{img.job.status} and id: #{img.job.id}"
      sleep 0.1 # poll for updated job status
      img = Image.find_by_id(img.id)
      puts "status: '#{img.job.status}', #{img.job.id} and #{Jobs::Job.count(:conditions => ["status = 'complete'"])} completed"
    end

    assert_equal 'complete', img.job.status
    assert File.exist?(img.thumb_path)
  end

  def test_high_load_thumb_jobs

    images = []

    20.times do
      # create new message record
      image = Image.new :name => 'test',
                        :alt_text => 'sample',
                        :path => File.expand_path(File.join(File.dirname(__FILE__),'sample.png'))

      # save the new record, should trigger the image
      assert image.save
      images << image
    end

    images.each do|image|
      wait_image_job_complete_or_error(image)
    end
  end
 
  def test_file_search_job
    puts "call test_file_search_job"
  end

end
