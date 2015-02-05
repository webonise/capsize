'convert recipes from the capistrano2 syntax'
task :copy_recipes => :environment do
  require "active_record"

  class Recipe < ActiveRecord::Base
  end

  recipe_collection = []

  Recipe.establish_connection{
    :capsize_production
  }

  Recipe.all.each do |recipe|
    recipe_collection << recipe
    Recipe.destroy(recipe.id)
  end

  recipe_collection.each do |r|
    replace_callbacks(r)
    replace_run_syntax(r)
    replace_role_syntax(r)
    Recipe.create(r.attributes)
  end

end

def replace_callbacks(r)
  CALLBACK_HASH.each do |callback, task|
    r.body = r.body.gsub(/#{callback}/, "#{task}" )
  end
end

def replace_run_syntax(r)
  r.body = r.body.gsub(/run\s*"/, "execute \"" )
end

def replace_role_syntax(r)
  r.body = r.body.gsub(/(task.*\sdo\s)(.+?\send\s)/m) { "#{$1}\n\ton roles :app do\n#{$2}\n\tend\n" }
  if r.body =~ /, :roles => :(.*)do/
    r.body = r.body.gsub(/, :roles => :(.*)do/, ' do')
  end
end

CALLBACK_HASH = { "deploy:update_code" => "deploy:updating",
                  "deploy:finalize_update" => "deploy:updated",
                  "deploy:restart" => "deploy:finished",
                  "current_release" => "current_path",
}
