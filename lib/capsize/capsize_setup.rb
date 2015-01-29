include Capistrano::DSL
include ApplicationHelper


namespace :load do
  task :defaults do
    load 'capistrano/defaults.rb'
  end
end

task :custom_log do
  deployment = Deployment.find(ENV['DEPLOYMENT_ID'])
  $stdout.rewind
  $stdout.each_line do |line|
    deployment.log = (deployment.log || '') + line
  end
  deployment.save!
  Rake::Task["custom_log"].reenable
end

def capsize_setup(stage)
  Rake::Task.define_task(stage.name) do
    set(:stage, stage.name.to_sym)

    invoke 'load:defaults'
    load rooted("#{stage.project.capsize_project_name}/deploy.rb")
    load rooted("#{stage.project.capsize_project_name}/#{stage.name}.rb")
    load "capistrano/#{fetch(:scm)}.rb"
    I18n.locale = fetch(:locale, :en)
    configure_backend
  end
  require 'capistrano/dotfile'
end
