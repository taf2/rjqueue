require 'RMagick'
require 'jobs/client'

# require test models
$:.unshift File.join(File.dirname(__FILE__),'..','lib')
require 'image'

class ImageThumbJob < Jobs::Base
  def execute
    #@logger.debug("lookup record: #{@record.data[:id].inspect} #{Image.connection.inspect}")
    # fetch the record to process
    image_record = Image.find_by_id( @record.data[:id].to_i )

    # read the image into memory
    image = Magick::Image.read(image_record.path).first

    # scale the image to the given dimensions
    image.change_geometry!( @record.data[:size] ) { |cols,rows,img|
      img.resize!(cols < 1 ? 1 : cols, rows < 1 ? 1 : rows)
    }

    # save the thumbnail, where we can find it later
    image.write image_record.thumb_path

    # save the record
    image_record.save
  end
end
