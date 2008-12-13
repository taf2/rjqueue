class Image < ActiveRecord::Base
  include Jobs::Scheduler

  has_one :job, :class_name => 'Jobs::Job', :as => :taskable, :dependent => :destroy

  after_create :filter_image

  def filter_image
    # schedule the attached image to be scaled to 64x32
    schedule(:image_thumb,{:id => self.id, :size => '64x32' })
  end

  def thumb_path
    extname = File.extname(self.path)
    pathname = self.path.gsub(/#{extname}$/,'')
    "#{pathname}-thumb#{extname}"
  end
end
