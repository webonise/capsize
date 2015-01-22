include Capistrano::DSL


namespace :load do
  task :defaults do
    load 'capistrano/defaults.rb'
  end
end

def capsize_setup(stage)
  Rake::Task.define_task(stage) do
    set(:stage, stage.to_sym)

    invoke 'load:defaults'
    load "./capsize_projects/test_capistrano3/deploy.rb"
    load "./capsize_projects/test_capistrano3/#{stage}.rb"
    load "capistrano/#{fetch(:scm)}.rb"
    I18n.locale = fetch(:locale, :en)
    configure_backend
  end
  require 'capistrano/dotfile'
end
