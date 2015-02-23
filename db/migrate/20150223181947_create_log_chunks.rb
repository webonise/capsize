class CreateLogChunks < ActiveRecord::Migration
  def self.up
    create_table :log_chunks do |t|
      t.string :content
      t.integer :deployment_id

      t.timestamps
    end
  end

  def self.down
    drop_table :log_chunks
  end
end
