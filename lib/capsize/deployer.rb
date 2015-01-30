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

      if(@deployment.send(:task) && !@deployment.new_record?)
        # a read deployment
        @logger = Capsize::Logger.new(deployment)
        @logger.level = Capsize::Logger::TRACE
        validate
      else
        # a fake deployment in order to access tasks
        @logger = Capsize::Logger.new(deployment)
      end
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
      config = instantiate_configuration
      set_project_and_stage_names(config)
      find_or_create_project_dir(config.fetch(:capsize_project))
      write_deploy(config)
      write_stage(deployment.stage)

      load_requirements
      capsize_setup(deployment.stage)
      set_output
      status = catch(:abort_called_by_capistrano){
        Capistrano::Application.invoke("#{deployment.stage.name}")
        Capistrano::Application.invoke(options[:actions])
      }
      close_output

      if status == :capistrano_abort
        false
      else
        config
      end
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

    # override in order to use DB logger
    def instantiate_configuration #:nodoc:
      config = Capsize::Configuration.new
      config.logger = logger
      config
    end

    def set_up_config(config)
      set_project_and_stage_names(config)
      set_stage_configuration(config)
      set_stage_roles(config)

      load_stage_custom_recipes(config)
      config
    end

    # sets the Capsize::Logger instance on the configuration,
    # so that it gets used by the SCM#logger
    def set_capsize_logger(config)
      config.set :logger, logger
    end

    # sets the stage configuration on the Capistrano configuration
    def set_stage_configuration(config)
      deployment.stage.non_prompt_configurations.each do |effective_conf|
        value = resolve_references(config, effective_conf.value)
        config.set effective_conf.name.to_sym, Deployer.type_cast(value)
      end
      deployment.prompt_config.each do |k, v|
        v = resolve_references(config, v)
        config.set k.to_sym, Deployer.type_cast(v)
      end
    end

    def resolve_references(config, value)
      value = value.dup.to_s
      references = value.scan(/#\{([a-zA-Z_]+)\}/)
      unless references.blank?
        references.flatten.compact.each do |ref|
          conf_param_refence = deployment.effective_and_prompt_config.select{|conf| conf.name.to_s == ref}.first
          if conf_param_refence
            value.sub!(/\#\{#{ref}\}/, conf_param_refence.value) if conf_param_refence.value.present?
          elsif config.exists?(ref)
            build_in_value = config.fetch(ref)
            value.sub!(/\#\{#{ref}\}/, build_in_value.to_s)
          end
        end
      end
      value
    end

    # load the project's custom tasks
    def load_project_template_tasks(config)
      config.load(:string => deployment.stage.project.tasks)
    end

    # load custom project recipes
    def load_stage_custom_recipes(config)
      begin
        deployment.stage.recipes.ordered.each do |recipe|
          logger.info("loading stage recipe '#{recipe.name}' ")
          config.load(:string => recipe.body)
        end
      rescue SyntaxError, LoadError => e
        raise Capistrano::Error, "Problem loading custom recipe: #{e.message}"
      end
    end

    # sets the roles on the Capistrano configuration
    def set_stage_roles(config)
      deployment.deploy_to_roles.each do |r|

        # create role attributes hash
        role_attr = r.role_attribute_hash

        if role_attr.blank?
          config.role r.name, r.hostname_and_port
        else
          config.role r.name, r.hostname_and_port, role_attr
        end
      end
    end

    # sets capsize_project and capsize_stage to corrosponding values
    def set_project_and_stage_names(config)
      config.set(:capsize_project, deployment.stage.project.capsize_project_name)
      config.set(:capsize_stage, deployment.stage.capsize_stage_name)
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

    # returns a list of all tasks defined for this deployer
    def list_tasks
      [{:name => "deploy:rollback", :description => nil}, {:name => "deploy:cleanup", :description => nil}]
    end

    def find_or_create_project_dir(project)
      FileUtils.mkdir_p(rooted("#{project}"))
    end

    def write_deploy(config)
      File.open(rooted("#{config.fetch(:capsize_project)}/deploy.rb"), 'w+') do |f|
        f.puts "stages = '#{deployment.stage.name}'"
        deployment.stage.project.configuration_parameters.each do |parameter|
          f.puts "set :#{parameter.name}, '#{parameter.value}'"
        end
          f.puts "after :#{deployment.stage.name}, :custom_log"
        %w{deploy:started deploy:updated deploy:published deploy:finished}.each do |task|
          # f.puts before_flow(task)
          f.puts after_flow(task)
        end
      end
    end

    def write_stage(stage)
      File.open(rooted("#{stage.project.capsize_project_name}/#{stage.name}.rb"), 'w+') do |f|
        stage.roles.each do |role|
          f.puts "role :#{role.name}, %w{#{find_host_user(stage.project)}@#{role.host.name}}"
        end
        stage.configuration_parameters.each do |parameter|
          f.puts "set :#{parameter.name}, '#{parameter.value}'"
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

    def before_flow(task)
      "before '#{task}', :custom_log"
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
