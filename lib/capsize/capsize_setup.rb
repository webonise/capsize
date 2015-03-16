include Capistrano::DSL
include ApplicationHelper


namespace :load do
  task :defaults do
    load 'capistrano/defaults.rb'
  end
end

def capsize_setup(stage)
  Rake::Task.define_task(stage.name) do

    invoke 'load:defaults'
    load rooted("#{stage.project.capsize_project_name}/deploy.rb")
    load rooted("#{stage.project.capsize_project_name}/#{stage.name}.rb")
    load "capistrano/#{fetch(:scm)}.rb"
    I18n.locale = fetch(:locale, :en)
    configure_backend
  end
end
require 'capistrano/dotfile'
