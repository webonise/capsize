require 'capistrano/all'

desc 'load cap tasks to the database'
task :load_cap_tasks do
  Rake.application = Capistrano::Application.new
  Rake.application.init
  Rake.application.load_rakefile
  puts Rake.application.tasks
end
