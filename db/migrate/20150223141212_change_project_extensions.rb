class ChangeProjectExtensions < ActiveRecord::Migration
  def self.up
    change_column :projects, :extensions, :string, :default => []
    Project.where(:extensions => nil).update_all(:extensions => [])
  end

  def self.down
    change_column :projects, :extensions, :string, :default => nil
  end
end
