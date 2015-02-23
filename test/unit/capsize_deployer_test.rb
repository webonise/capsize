require File.dirname(__FILE__) + '/../test_helper'

class Capsize::DeployerTest < ActiveSupport::TestCase
  include ApplicationHelper

  def setup
    @project = create_new_project(:template => 'pure_file')
    @stage = create_new_stage(:project => @project)
    @host = create_new_host

    @role = create_new_role(:stage => @stage, :host => @host, :name => 'web')

    assert @stage.prompt_configurations.empty?

    @deployment = create_new_deployment(:stage => @stage, :task => 'master:do')
  end

  def test_initialization
    # no deployment
    assert_raise(ArgumentError){
      deployer = Capsize::Deployer.new
    }

    # deployment + role ==> works
    assert_nothing_raised{
      deployer = Capsize::Deployer.new(@deployment)
    }

    # deployment with no role
    assert_raise(ArgumentError){
      @stage.roles.clear
      assert @deployment.roles(true).empty?
      deployer = Capsize::Deployer.new(@deployment)
    }
  end

  def test_role_attributes
    # prepare stage + roles
    stage = create_new_stage

    web_role = stage.roles.build(:name => 'web', :host_id => @host.id, :primary => 1, :no_release => 0)
    web_role.save!
    assert !web_role.no_release?
    assert web_role.primary?

    app_role = stage.roles.build(:name => 'app', :host_id => @host.id, :primary => 0, :no_release => 1, :ssh_port => '99')
    app_role.save!
    assert app_role.no_release?
    assert !app_role.primary?

    db_role = stage.roles.build(:name => 'db', :host_id => @host.id, :primary => 1, :no_release => 1, :ssh_port => 44)
    db_role.save!
    assert db_role.no_release?
    assert db_role.primary?
  end

  def test_excluded_hosts
    # prepare stage + roles
    stage = create_new_stage
    dead_host = create_new_host

    web_role = stage.roles.build(:name => 'web', :host_id => @host.id)
    web_role.save!

    app_role = stage.roles.build(:name => 'app', :host_id => @host.id)
    app_role.save!

    db_role = stage.roles.build(:name => 'db', :host_id => dead_host.id)
    db_role.save!

    stage.reload

    deployment = create_new_deployment(:stage => stage)
    deployment.excluded_host_ids = [dead_host.id]
    deployment.save!
    assert_equal [web_role, app_role].map(&:id).sort, deployment.deploy_to_roles.map(&:id).sort
  end

  def test_type_casts
    assert_equal '', Capsize::Deployer.type_cast('')
    assert_equal nil, Capsize::Deployer.type_cast('nil')
    assert_equal true, Capsize::Deployer.type_cast('true')
    assert_equal false, Capsize::Deployer.type_cast('false')
    assert_equal :sym, Capsize::Deployer.type_cast(':sym')
    assert_equal 'abc', Capsize::Deployer.type_cast('abc')
    assert_equal '/usr/local/web', Capsize::Deployer.type_cast('/usr/local/web')
    assert_equal 'https://svn.domain.com', Capsize::Deployer.type_cast('https://svn.domain.com')
    assert_equal 'svn+ssh://svn.domain.com/svn', Capsize::Deployer.type_cast('svn+ssh://svn.domain.com/svn')
    assert_equal 'la le lu 123', Capsize::Deployer.type_cast('la le lu 123')
  end

  def test_type_cast_cvs_root
    assert_equal ":ext:msaba@xxxxx.xxxx.com:/project/cvsroot", Capsize::Deployer.type_cast(":ext:msaba@xxxxx.xxxx.com:/project/cvsroot")
  end

  def test_type_cast_arrays
    assert_equal ['foo', :bar, 'bam'], Capsize::Deployer.type_cast("[foo, :bar, 'bam']")
    assert_equal ['1', '2', '3', '4'], Capsize::Deployer.type_cast('[1, 2, 3, 4]')
  end

  def test_type_cast_arrays_with_embedded_content
    assert_equal ['1', '2', :a, true], Capsize::Deployer.type_cast('[1, 2, :a, true]')
    # TODO the parser is very simple for now :-(
    assert_not_equal ['1', ['3', 'foo'], :a, true], Capsize::Deployer.type_cast('[1, [3, "foo"], :a, true]')
  end

  def test_type_cast_hashes
    assert_equal({:a => :b}, Capsize::Deployer.type_cast("{:a => :b}"))
    assert_equal({:a => '1'}, Capsize::Deployer.type_cast("{:a => 1}"))
    assert_equal({'1' => '1', '2' => '2'}, Capsize::Deployer.type_cast("{1 => 1, 2 => 2}"))
  end

  def test_type_cast_hashes_with_embedded_content
    # TODO the parser is very simple for now :-(
    assert_not_equal({'1' => '1', '2' => [:a, :b, '1']}, Capsize::Deployer.type_cast("{1 => 1, 2 => [:a, :b, 1]}"))
  end

  def test_type_cast_hashes_does_not_cast_evaluations
    assert_equal '#{foo}', Capsize::Deployer.type_cast('#{foo}')
    assert_equal 'a#{foo}', Capsize::Deployer.type_cast('a#{foo}')
    assert_equal 'be #{foo}', Capsize::Deployer.type_cast('be #{foo}')
    assert_equal '#{foo} 123', Capsize::Deployer.type_cast(' #{foo} 123')
  end

  def test_task_invokation_successful
    @deployment = create_new_deployment(:stage => @stage, :task => 'deploy:rollback')

    deployer = Capsize::Deployer.new(@deployment)
    deployer.stubs(:execute!).returns(true)
    deployer.invoke_task!

    assert_equal @stage, @deployment.stage
    assert_equal [@role.id], @deployment.roles.collect(&:id)
    assert_equal 'deploy:rollback', @deployment.task
    assert @deployment.completed?
    assert @deployment.success?

    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_task_invokation_not_successful

    @deployment = create_new_deployment(:stage => @stage, :task => 'deploy:updating')

    deployer = Capsize::Deployer.new(@deployment)
    deployer.stubs(:execute!).returns(false)
    deployer.invoke_task!

    assert_equal 'deploy:updating', @deployment.task
    assert @deployment.completed?
    assert !@deployment.success?

    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_db_logging
    @deployment = create_new_deployment(:stage => @stage, :task => 'deploy:updating')

    # do a random deploy
    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!

    # the log in the DB should not be empty
    @deployment.reload
    assert_match(/Writing deploy configuration to #{Regexp.escape(@stage.project.capsize_project_name)}\/deploy.rb/, @deployment.log)
    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_db_logging_if_task_vars_incomplete
    # create a deployment
    @deployment = create_new_deployment(:stage => @stage, :task => 'deploy:default')

    # and after creation
    # prepare stage configuration to miss important vars
    @project.configuration_parameters.delete_all
    @stage.configuration_parameters.delete_all

    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!

    # the log in the DB should not be empty
    @deployment.reload
    assert_match(/Please define the configuration parameters to deploy your application/, @deployment.log) # ' fix highlighting
    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_handling_of_prompt_configuration
    stage_with_prompt = create_new_stage(:name => 'prod', :project => @project)
    role = create_new_role(:stage => stage_with_prompt)
    assert stage_with_prompt.deployment_possible?, stage_with_prompt.deployment_problems.inspect

    # add a config value that wants a promp
    stage_with_prompt.configuration_parameters.create!(:name => 'password', :prompt_on_deploy => 1)
    assert !stage_with_prompt.prompt_configurations.empty?

    # create the deployment
    deployment = create_new_deployment(:stage => stage_with_prompt, :task => 'deploy', :prompt_config => {'password' => 'pass1234'})

    write_deployer_files(deployment)
    file = File.open(rooted("#{@project.capsize_project_name}/#{stage_with_prompt.name}.rb"))
    contents = file.read

    assert_match(/set :password, 'pass1234'/, contents)
    remove_directory(stage_with_prompt.project.capsize_project_name)
  end

  def test_loading_of_template_tasks
    @project.template = 'mongrel_rails'
    @project.save!

    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!
    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_custom_recipes
    recipe_1 = create_new_recipe(:name => 'Copy config files', :body => 'foobar here')
    @stage.recipes << recipe_1

    recipe_2 = create_new_recipe(:name => 'Merge JS files', :body => 'more foobar here')
    @stage.recipes << recipe_2

    assert_equal [@stage], recipe_1.stages
    assert_equal [@stage], recipe_2.stages
  end

  def test_load_order_of_recipes
    recipe_1 = create_new_recipe(:name => 'B', :body => 'foobar here')
    @stage.recipes << recipe_1

    recipe_2 = create_new_recipe(:name => 'A', :body => 'more foobar here')
    @stage.recipes << recipe_2
  end

  def test_handling_of_exceptions_during_command_execution
    deployer = Capsize::Deployer.new(@deployment)
    deployer.run_in_isolation do
      raise RuntimeError
    end
    deployer.invoke_task!
    remove_directory(@deployment.stage.project.capsize_project_name)


    @deployment.reload
    assert_match(/RuntimeError/, @deployment.log)
  end

  def test_deploy_file_is_written
    assert !File.exist?(rooted("#{@deployment.stage.project.capsize_project_name}/deploy.rb"))
    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!
    assert File.exist?(rooted("#{@deployment.stage.project.capsize_project_name}/deploy.rb"))
    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_stage_file_is_written
    assert !File.exist?(rooted("#{@deployment.stage.project.capsize_project_name}/#{@deployment.stage.name}.rb"))
    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!
    assert File.exist?(rooted("#{@deployment.stage.project.capsize_project_name}/#{@deployment.stage.name}.rb"))
    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_string_parameters_written_correctly
    deploy_configs = [ { :name => 'app_name', :value => 'madeupname' },
                       { :name => 'deploy_to', :value => 'route66'},
                       { :name => 'password', :value => '99redballoons'},
                       { :name => 'super_password', :value => '456!!!what?i?s?8'}
                     ]
    contents = write_config_params(deploy_configs)

    deploy_configs.each do |config|
      match_string_param(config[:name], config[:value], contents)
    end

    remove_directory(@stage.project.capsize_project_name)
  end

  def test_non_string_parameters_written_correctly
    deploy_configs = [ { :name => 'pty', :value => 'true' },
                       { :name => 'keep_releases', :value => '80'},
                       { :name => 'linked_dirs', :value => '%w{ made_up_dir }'},
                       { :name => 'nothing', :value => 'nil' }
                     ]

    contents = write_config_params(deploy_configs)

    deploy_configs.each do |config|
      match_non_string_param(config[:name], config[:value], contents)
    end

    remove_directory(@stage.project.capsize_project_name)
  end

  def test_output_logs_in_browser_log
    deployer = Capsize::Deployer.new(@deployment)
    deployer.run_in_isolation do
      print 'thisshouldshowup'
    end
    assert $stdout == STDOUT

    assert_match /thisshouldshowup/, @deployment.log
  end

  def test_tasks_load
    deployer = Capsize::Deployer.new(@deployment)
    tasks = deployer.list_tasks

    assert tasks.include?('load:defaults'), tasks.inspect
    assert tasks.include?('deploy:rollback')
  end

  def test_extensions_tasks_load
    project = @deployment.stage.project
    assert project.extensions.include?('rvm') && project.extensions.include?('bundler')
    assert_equal project.extensions.length, 2

    deployer = Capsize::Deployer.new(@deployment)
    tasks = deployer.list_tasks

    assert tasks.include?('bundler:install')
    assert tasks.include?('rvm:hook')
    assert !tasks.include?('deploy:migrate')
    assert !tasks.include?('deploy:assets:precompile')

    project.extensions = ['rails/assets', 'rails/migrations']
    project.save!
    tasks = deployer.list_tasks

    assert !tasks.include?('bundler:install')
    assert !tasks.include?('rvm:hook')
    assert tasks.include?('deploy:migrate')
    assert tasks.include?('deploy:assets:precompile')
  end

  def test_task_load_error
    deployer = Capsize::Deployer.new(@deployment)
    deployer.stubs(:run_in_isolation).returns(false)
    tasks = deployer.list_tasks

    assert_equal tasks, ['Error Loading Tasks']
  end

  def test_runs_in_isolation
    deployer = Capsize::Deployer.new(@deployment)
    this_process = Process.pid

    output = deployer.run_in_isolation do
      Process.pid
    end

    child_process = output.gsub("\n", '').to_i

    assert_not_equal this_process, child_process
    assert_equal Process.pid, this_process
    assert_raise(Errno::ESRCH) { Process.getpgid(child_process) }
  end

  protected

  def write_config_params(configs)
    deployment = create_new_deployment(:stage => @stage)

    configs.each do |config|
      @stage.project.configuration_parameters.create(config)
    end

    write_deployer_files(deployment)
    file = File.open(rooted("#{@stage.project.capsize_project_name}/deploy.rb"))
    file.read
  end

  def match_string_param(name, value, contents)
    assert_match /set :#{name}, '#{Regexp.quote(value)}'/, contents
    assert_match /\nset :#{name}, '#{Regexp.quote(value)}'\n/m, contents
  end

  def match_non_string_param(name, value, contents)
    assert_match /set :#{name}, #{Regexp.quote(value)}/, contents
    assert_match /\nset :#{name}, #{Regexp.quote(value)}\n/m, contents
  end

  def write_deployer_files(deployment)
    deployer = Capsize::Deployer.new(deployment)
    deployer.find_or_create_project_dir
    deployer.write_deploy
    deployer.write_stage
  end

  def remove_directory(project)
    FileUtils.rm_rf(rooted("#{project}"))
  end

end
