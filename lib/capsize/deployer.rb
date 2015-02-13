require 'find'
require 'fileutils'


module Capsize
  class Deployer
    include ApplicationHelper
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
      @logger = Capsize::Logger.new(@deployment)
      @logger.level = Capsize::Logger::TRACE

      validate if !@deployment.new_record? && @deployment.task
    end

    # validates this instance
    # raises on ArgumentError if not valid
    def validate
      raise ArgumentError, 'The given deployment has no roles and thus can not be deployed!' if deployment.roles.empty?
    end

    def list_tasks
      output = run_in_isolation do
        require 'capistrano/all'
        cap = Capistrano::Application.new
        Rake.application = cap
        cap.init
        cap.load_rakefile
        cap.tasks
      end
      return ["Error Loading Tasks"] unless output
      cap_tasks = []
      output.each_line { |task| cap_tasks << task }
      cap_tasks.map { |task| task.gsub("\n", '') }
    end

    # actual invokment of a given task (through @deployment)
    def invoke_task!
      options[:actions] = deployment.task

      unless execute!
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


      status = run_in_isolation do
        load_requirements
        capsize_setup(@stage)
        set_output
        Capistrano::Application.invoke("#{@stage.name}")
        after_stage_invokations
        Capistrano::Application.invoke(options[:actions])
        close_output
      end

      status

    rescue Exception => error
      handle_error(error)
      return false
    end

    def run_in_isolation
      read, write = IO.pipe

      pid = fork do
        read.close
        begin
          result = yield
        rescue Exception => error
          handle_error(error)
          result = nil
        end
        write.puts result
        exit!(0)
      end

      write.close
      result = read.read
      Process.wait(pid)
      return false if result == "\n"
      result
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

    def print_parameter(parameter)
      name = parameter.name
      val = parameter.value

      val = deployment.prompt_config[name] if parameter.prompt?

      return nil if val.nil?
      val.strip!
      return set_string_parameter(name, val) if val =~ /\A\d+\D+/

      case val
      when 'true', 'false', 'nil'
        return set_non_string_parameter(name, val)
      end

      case val[0]
      when ":", "%", "[", "{", /\d/
        set_non_string_parameter(name, val)
      else
        set_string_parameter(name, val)
      end
    end

    def set_string_parameter(name, val)
      "set :#{name}, '#{val}'"
    end

    def set_non_string_parameter(name, val)
      "set :#{name}, #{val}"
    end

    # override in order to use DB logger
    def handle_error(error) #:nodoc:
      case error
      when Net::SSH::AuthenticationFailed
        logger.important "authentication failed for `#{error.message}'"
      else
        logger.important error.message + "\n" + error.backtrace.join("\n")
      end
    end

    def find_or_create_project_dir
      FileUtils.mkdir_p(rooted("#{@project_name}"))
    end

    def write_deploy
      @logger.info("Writing deploy configuration to #{@project_name}/deploy.rb")
      if @project.configuration_parameters.empty?
        raise ArgumentError, logger.important("Please define the configuration parameters to deploy your application")
      end
      File.open(rooted("#{@project_name}/deploy.rb"), 'w+') do |f|
        @project.configuration_parameters.each do |parameter|
          f.puts print_parameter(parameter)
        end
          f.puts after_flow(@stage.name)
        %w{deploy:started deploy:updated deploy:published deploy:finished}.each do |task|
          f.puts after_flow(task)
        end
      end
    end

    def write_stage
      @logger.info("Writing stage configuration to #{@project_name}/#{@stage.name}.rb")
      File.open(rooted("#{@project_name}/#{@stage.name}.rb"), 'w+') do |f|
        @stage.roles.each do |role|
          unless @deployment.excluded_host_ids.include?(role.host_id.to_s)
            f.puts "role :#{role.name}, %w{#{find_host_user(@project)}@#{role.host.name}}"
          end
        end
        @stage.configuration_parameters.each do |parameter|
          f.puts print_parameter(parameter)
        end
        deployment.stage.recipes.each do |recipe|
          f.puts recipe.body
        end
      end
    end

    def find_host_user(project)
      user = project.configuration_parameters.find_by_name('user')
      raise ArgumentError, @logger.important("You must define the user parameter before deploying") if user.nil?
      user.value
    end

    def load_requirements
      require "capistrano/all"
      require "capsize/capsize_setup"
      require "capistrano/deploy"
      require 'capistrano/rvm'
      require 'capistrano/bundler'
      require 'capistrano/rails/migrations'
      require 'capistrano/rails/assets'
    end

    def after_stage_invokations
      Capistrano::Application.invoke("rvm:hook")
      Capistrano::Application.invoke("rvm:check")
      Capistrano::Application.invoke("bundler:map_bins")
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
