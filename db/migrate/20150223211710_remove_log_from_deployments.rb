class RemoveLogFromDeployments < ActiveRecord::Migration
  def self.up
    remove_column :deployments, :log
  end

  def self.down
    add_column :deployments, :log, :text
  end
end
