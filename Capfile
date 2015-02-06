require 'capistrano/setup'
require 'capistrano/deploy'

# Includes tasks from other gems included in your Gemfile
#
require 'capistrano/rvm'
require 'capistrano/bundler'
require 'capistrano/rails/migrations'
require 'capistrano/rails/assets'


Dir.glob('lib/capistrano/tasks/*.rake').each { |r| import r }
