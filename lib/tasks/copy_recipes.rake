desc 'copy recipes from the capistrano2/webistrano database to this one'
task :copy_recipe => :environment do
  require "active_record"

  class Recipe < ActiveRecord::Base
  end

  recipe_collection = []

  Recipe.establish_connection{
    :webistrano_development
  }

  Recipe.all.each do |recipe|
    recipe_collection << recipe
  end

  recipe_collection.each do |r|
    replace_callbacks(r)
    Recipe.create(r.attributes)
  end

end

def replace_callbacks(r)
  CALLBACK_HASH.each do |callback, task|
    r.body = r.body.gsub(/#{callback}/, "#{task}" )
  end
end

CALLBACK_HASH = { "deploy:update_code" => "deploy:updated",
                  "deploy:restart" => "deploy:restart",
                  "deploy:create_symlink" => "deploy:create_symlink",
                  "deploy:finalize_update" => "deploy:updated",
                }
