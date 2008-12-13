class CreateTestData < ActiveRecord::Migration

  def self.up
    create_table :messages, :force => true do |t|
      t.string :subject
      t.string :content
      t.integer :image_id
    end

    create_table :images, :force => true do |t|
      t.string :name
      t.string :alt_text
      t.string :path
    end
  end

end
