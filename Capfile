require 'capistrano/setup'
require 'capistrano/deploy'

# Includes tasks from other gems included in your Gemfile
#
require 'capistrano/rvm'
require 'capistrano/bundler'
require 'capistrano/rails/migrations'


Dir.glob('lib/capistrano/tasks/*.cap').each { |r| import r }
