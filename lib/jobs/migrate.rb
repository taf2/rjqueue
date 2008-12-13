class CreateJobs < ActiveRecord::Migration
  def self.up
    create_table :jobs, :force => true do |t|
      t.string   :name,                          :null => false
      t.text     :data
      t.string   :status
      t.datetime :created_at
      t.datetime :updated_at
      t.integer  :duration
      t.integer  :taskable_id
      t.string   :taskable_type
      t.text     :details
      t.boolean  :locked,     :default => false, :null => false
      t.integer  :attempts,   :default => 0,     :null => false
    end

    add_index :jobs, [:status, :locked]
  end
end
