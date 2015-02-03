require 'find'
require 'fileutils'
require 'capistrano/all'


module Capsize
  class Deployer
    include ApplicationHelper
    include Capistrano::DSL
    # Mix-in the Capistrano behavior
    # holds the capistrano options, see capistrano/lib/capistrano/cli/options.rb
    attr_accessor :options

    # deployment (AR model) that will be deployed
    attr_accessor :deployment

    attr_accessor :logger

    attr_reader :browser_log

    def initialize(deployment)
      @options = {
        :recipes => [],
        :actions => [],
        :vars => {},
        :pre_vars => {},
        :verbose => 3
      }

      @deployment = deployment
      @stage = deployment.stage
      @project = deployment.stage.project
      @project_name = deployment.stage.project.capsize_project_name
    end

    # validates this instance
    # raises on ArgumentError if not valid
    def validate
      raise ArgumentError, 'The given deployment has no roles and thus can not be deployed!' if deployment.roles.empty?
    end

    # actual invokment of a given task (through @deployment)
    def invoke_task!
      options[:actions] = deployment.task

      case execute!
      when false
        deployment.complete_with_error!
        false
      else
        deployment.complete_successfully!
        true
      end
    end

    def execute!
      find_or_create_project_dir
      write_deploy
      write_stage

      load_requirements
      capsize_setup(@stage)
      set_output
      status = catch(:abort_called_by_capistrano){
        Capistrano::Application.invoke("#{@stage.name}")
        Capistrano::Application.invoke(options[:actions])
      }
      close_output

      status != :capistrano_abort

    rescue Exception => error
      handle_error(error)
      return false
    end


    # save the revision in the DB if possible
    def save_revision(config)
      if config.fetch(:real_revision)
        @deployment.revision = config.fetch(:real_revision)
        @deployment.save!
      end
    rescue => e
      logger.important "Could not save revision: #{e.message}"
    end

    # saves the process ID of this running deployment in order
    # to be able to kill it
    def save_pid
      @deployment.pid = Process.pid
      @deployment.save!
    end

    # casts a given string to the correct Ruby value
    # e.g. 'true' to true and ':sym' to :sym
    def self.type_cast(val)
      return nil if val.nil?

      val.strip!
      case val
      when 'true'
        true
      when 'false'
        false
      when 'nil'
        nil
      when /\A\[(.*)\]/
        $1.split(',').map{|subval| type_cast(subval)}
      when /\A\{(.*)\}/
        $1.split(',').collect{|pair| pair.split('=>')}.inject({}) do |hash, (key, value)|
	        hash[type_cast(key)] = type_cast(value)
	        hash
	      end
      else # symbol or string
        if cvs_root_defintion?(val)
          val.to_s
        elsif val.index(':') == 0
          val.slice(1, val.size).to_sym
        elsif match = val.match(/'(.*)'/) || val.match(/"(.*)"/)
          match[1]
        else
          val
        end
      end
    end

    def self.cvs_root_defintion?(val)
      val.index(':') == 0 && val.scan(":").size > 1
    end

    # override in order to use DB logger
    def handle_error(error) #:nodoc:
      case error
      when Net::SSH::AuthenticationFailed
        logger.important "authentication failed for `#{error.message}'"
      else
        logger.important(error.message + "\n" + error.backtrace.join("\n"))
      end
    end

    def find_or_create_project_dir
      FileUtils.mkdir_p(rooted("#{@project_name}"))
    end

    def write_deploy
      File.open(rooted("#{@project_name}/deploy.rb"), 'w+') do |f|
        @project.configuration_parameters.each do |parameter|
          f.puts "set :#{parameter.name}, '#{parameter.value}'"
        end
          f.puts "after :#{@stage.name}, :custom_log"
        %w{deploy:started deploy:updated deploy:published deploy:finished}.each do |task|
          f.puts after_flow(task)
        end
      end
    end

    def write_stage
      File.open(rooted("#{@project_name}/#{@stage.name}.rb"), 'w+') do |f|
        @stage.roles.each do |role|
          f.puts "role :#{role.name}, %w{#{find_host_user(@project)}@#{role.host.name}}"
        end
        @stage.configuration_parameters.each do |parameter|
          f.puts "set :#{parameter.name}, '#{parameter.value}'"
        end
        deployment.stage.recipes.each do |recipe|
          f.puts recipe.body
        end
      end
    end

    def find_host_user(project)
      project.configuration_parameters.find_by_name('user').value
    end

    def load_requirements
      require "capsize/capsize_setup"
      require "capistrano/deploy"
      require 'capistrano/rvm'
      require 'capistrano/bundler'
    end

    def after_flow(task)
      "after '#{task}', :custom_log"
    end

    def set_output
      @browser_log = StringIO.new
      $stdout = @browser_log
      $stdout.sync = true
      ENV['deployment_id'] = deployment.id.to_s
    end

    def close_output
      $stdout = STDOUT
    end

  end
end
