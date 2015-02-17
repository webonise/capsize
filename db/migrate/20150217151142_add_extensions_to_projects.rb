class AddExtensionsToProjects < ActiveRecord::Migration
  def self.up
    add_column :projects, :extensions, :string
  end

  def self.down
    remove_column :projects, :extensions
  end
end
