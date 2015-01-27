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

  teardown do
    remove_directory(@stage.project)
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

  def test_setting_of_configuration_parameters_on_capistrano_configuration
    # create some configuration entries for the stage
    config = @stage.configuration_parameters.build(:name => 'stage_specific', :value => 'xxxxx'); config.save!
    config = @stage.configuration_parameters.build(:name => 'stage_specific2', :value => 'testapp'); config.save!

    # create another role for this stage
    app_role = @stage.roles.build(:name => 'app', :host_id => @host.id, :primary => 1)
    app_role.save!

    # prepare Mocks
    #

    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:load)
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:find_and_execute_task)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:fetch).with(:scm)

    # now the interesting part
    # variable setting
    mock_cap_config.expects(:set).with(:password, nil) # default by Cap
    mock_cap_config.expects(:set).with(:capsize_project, @project.name)
    mock_cap_config.expects(:set).with(:capsize_stage, @stage.name)

    # now we expect our Vars to be set
    # project vars
    ProjectConfiguration.templates['pure_file']::CONFIG.each do |k, v|
      if k.to_sym == :application
        mock_cap_config.expects(:set).with(k, Capsize::Deployer.type_cast( @project.name ) )
      else
        mock_cap_config.expects(:set).with(k, Capsize::Deployer.type_cast(v) )
      end
    end

    # stage vars and logger
    mock_cap_config.expects(:set).with{|x, y|
      case x
      when :stage_specific
        y == 'xxxxx'
      when :stage_specific2
        y == 'testapp'
      when :logger
        y.is_a? Capsize::Logger
      when :real_revision
        true
      else
        false
      end
    }.times(4)

    # roles
    mock_cap_config.expects(:role).with('web', @host.name)
    mock_cap_config.expects(:role).with('app', @host.name, {:primary => true})

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    # get things started
    deployer = Capsize::Deployer.new( create_new_deployment(:stage => @stage) )
    deployer.stubs(:save_revision)
    deployer.invoke_task!
  end

  def test_role_attributes
    # prepare stage + roles
    @stage = create_new_stage

    web_role = @stage.roles.build(:name => 'web', :host_id => @host.id, :primary => 1, :no_release => 0)
    web_role.save!
    assert !web_role.no_release?
    assert web_role.primary?

    app_role = @stage.roles.build(:name => 'app', :host_id => @host.id, :primary => 0, :no_release => 1, :ssh_port => '99')
    app_role.save!
    assert app_role.no_release?
    assert !app_role.primary?

    db_role = @stage.roles.build(:name => 'db', :host_id => @host.id, :primary => 1, :no_release => 1, :ssh_port => 44)
    db_role.save!
    assert db_role.no_release?
    assert db_role.primary?

    # prepare Mocks
    #

    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:load)
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:find_and_execute_task)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:fetch).with(:scm)

    # ignore vars
    mock_cap_config.stubs(:set)

    #
    # now check the roles
    #
    mock_cap_config.expects(:role).with('web', @host.name, {:primary => true})
    mock_cap_config.expects(:role).with('app', @host.name + ":99", {:no_release => true})
    mock_cap_config.expects(:role).with('db', @host.name + ":44", {:no_release => true, :primary => true})

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    # get things started
    deployer = Capsize::Deployer.new( create_new_deployment(:stage => @stage) )
    deployer.invoke_task!
  end

  def test_excluded_hosts
    # prepare stage + roles
    @stage = create_new_stage
    dead_host = create_new_host

    web_role = @stage.roles.build(:name => 'web', :host_id => @host.id)
    web_role.save!

    app_role = @stage.roles.build(:name => 'app', :host_id => @host.id)
    app_role.save!

    db_role = @stage.roles.build(:name => 'db', :host_id => dead_host.id)
    db_role.save!

    @stage.reload

    deployment = create_new_deployment(:stage => @stage, :excluded_host_ids => [dead_host.id])
    assert_equal [web_role, app_role].map(&:id).sort, deployment.deploy_to_roles.map(&:id).sort
    # prepare Mocks
    #

    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:load)
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:find_and_execute_task)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:fetch).with(:scm)

    # ignore vars
    mock_cap_config.stubs(:set)

    #
    # now check the roles
    #

    #mock_cap_config.expects(:role).with('db', @host.name)
    mock_cap_config.expects(:role).with('web', @host.name)
    mock_cap_config.expects(:role).with('app', @host.name)


    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    # get things started
    deployer = Capsize::Deployer.new( deployment )
    deployer.invoke_task!
  end

  def test_invoke_task
    assert_correct_task_called('deploy:setup')
    assert_correct_task_called('deploy:update')
    assert_correct_task_called('deploy:restart')
    assert_correct_task_called('deploy:stop')
    assert_correct_task_called('deploy:start')
  end

  def test_type_cast

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
    prepare_config_mocks

    @deployment = create_new_deployment(:stage => @stage, :task => 'deploy:rollback')

    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!

    assert_equal @stage, @deployment.stage
    assert_equal [@role.id], @deployment.roles.collect(&:id)
    assert_equal 'deploy:rollback', @deployment.task
    assert @deployment.completed?
    assert @deployment.success?

    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_task_invokation_not_successful
    # prepare mocks
    #

    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:load)
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:fetch).with(:scm)

    # vars
    mock_cap_config.stubs(:set)

    # roles
    mock_cap_config.stubs(:role)

    # the fun part
    # task execution throws an exception
    mock_cap_config.expects(:find_and_execute_task).raises(Capistrano::Error, 'sorry - no capistrano today')

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    @deployment = create_new_deployment(:stage => @stage, :task => 'deploy:update')

    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!

    assert_equal 'deploy:update', @deployment.task
    assert @deployment.completed?
    assert !@deployment.success?

    # check error message
    assert_match(/sorry - no capistrano today/, @deployment.log)
    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_db_logging
    @deployment = create_new_deployment(:stage => @stage, :task => 'deploy:update')

    # mocks
    mock_namespace = mock
    mock_namespace.stubs(:default_task)
    mock_namespace.stubs(:search_task)

    mock_task = mock
    mock_task.stubs(:namespace).returns(mock_namespace)
    mock_task.stubs(:body).returns(Proc.new{ Proc.new{} })
    mock_task.stubs(:fully_qualified_name).returns('deploy:update')
    mock_task.stubs(:name).returns('deploy:update')

    mock_cap_config = Capsize::Configuration.new
    mock_cap_config.logger = Capsize::Logger.new(@deployment)
    mock_cap_config.expects(:find_task).returns(mock_task)

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    # do a random deploy
    deployer = Capsize::Deployer.new(@deployment)
    deployer.stubs(:save_revision)
    deployer.invoke_task!

    # the log in the DB should not be empty
    @deployment.reload
    assert_equal "  * executing `deploy:update'\n", @deployment.log
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
    assert_match(/Please specify the repo_url that houses your application's code, set :repo_url, 'foo'/, @deployment.log) # ' fix highlighting
    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_handling_of_scm_error
    # prepare
    project = create_new_project(:template => 'rails')
    stage = create_new_stage(:project => @project)
    host = create_new_host(:name => '127.0.0.1')
    app_role = create_new_role(:name => 'app', :host => host, :stage => stage)
    web_role = create_new_role(:name => 'web', :host => host, :stage => stage)
    db_role = create_new_role(:name => 'db', :host => host, :stage => stage, :primary => 1)

    # mock Open4 to return an error
    mock_status = mock
    mock_status.expects(:exitstatus).returns(1)
    Open4.expects(:popen4).returns(mock_status)

    deployment = create_new_deployment(:stage => stage, :task => 'deploy:default')
    deployer = Capsize::Deployer.new(deployment)
    deployer.invoke_task!

    deployment.reload
    assert_match(/Local scm command failed/, deployment.log)
    remove_directory(deployment.stage.project.capsize_project_name)
  end

  def test_handling_of_open_scm_command_error
    # prepare
    project = create_new_project(:template => 'rails')
    stage = create_new_stage(:project => @project)
    host = create_new_host(:name => '127.0.0.1')
    app_role = create_new_role(:name => 'app', :host => host, :stage => stage)
    web_role = create_new_role(:name => 'web', :host => host, :stage => stage)
    db_role = create_new_role(:name => 'db', :host => host, :stage => stage, :primary => 1)

    # set the scm_command to something bogus in order to throw an error
    stage.configuration_parameters.build(:name => 'scm_command', :value => '/tmp/foobar_scm_command').save!

    deployment = create_new_deployment(:stage => stage, :task => 'deploy:default')
    deployer = Capsize::Deployer.new(deployment)
    deployer.invoke_task!

    deployment.reload
    assert_match(/Local scm command not found/, deployment.log)
    remove_directory(deployment.stage.project.capsize_project_name)
  end

  def test_handling_of_prompt_configuration
    stage_with_prompt = create_new_stage(:name => 'prod', :project => @project)
    role = create_new_role(:stage => stage_with_prompt)
    assert stage_with_prompt.deployment_possible?, stage_with_prompt.deployment_problems.inspect

    # add a config value that wants a promp
    stage_with_prompt.configuration_parameters.build(:name => 'password', :prompt_on_deploy => 1).save!
    assert !stage_with_prompt.prompt_configurations.empty?

    # create the deployment
    deployment = create_new_deployment(:stage => stage_with_prompt, :task => 'deploy', :prompt_config => {:password => '123'})

    deployer = Capsize::Deployer.new(deployment)
    deployer.invoke_task!
    remove_directory(stage_with_prompt.project.capsize_project_name)
  end

  def test_loading_of_template_tasks
    @project.template = 'mongrel_rails'
    @project.save!

    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:find_and_execute_task)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:fetch).with(:scm)

    # vars
    mock_cap_config.stubs(:set)

    # roles
    mock_cap_config.stubs(:role)

    #
    # now the interestin part, load
    #
    mock_cap_config.expects(:load).with('standard')
    mock_cap_config.expects(:load).with('deploy')
    mock_cap_config.expects(:load).with(:string => @project.tasks )

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    #
    # start


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

    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:find_and_execute_task)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:fetch).with(:scm)

    # vars
    mock_cap_config.stubs(:set)

    # roles
    mock_cap_config.stubs(:role)

    #
    # now the interestin part, load
    #
    mock_cap_config.expects(:load).with('standard')
    mock_cap_config.expects(:load).with('deploy')
    mock_cap_config.expects(:load).with(:string => @project.tasks )
    mock_cap_config.expects(:load).with(:string => recipe_1.body )
    mock_cap_config.expects(:load).with(:string => recipe_2.body )

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    #
    # start

    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!
    remove_directory(@deployment.stage.project.capsize_project_name)
  end

  def test_load_order_of_recipes
    recipe_1 = create_new_recipe(:name => 'B', :body => 'foobar here')
    @stage.recipes << recipe_1

    recipe_2 = create_new_recipe(:name => 'A', :body => 'more foobar here')
    @stage.recipes << recipe_2

    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:find_and_execute_task)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:fetch).with(:scm)

    # vars
    mock_cap_config.stubs(:set)

    # roles
    mock_cap_config.stubs(:role)

    #
    # now the interesting part, load
    #

    seq = sequence('recipe_loading')
    mock_cap_config.stubs(:load)
    mock_cap_config.expects(:load).with(:string => recipe_2.body ).in_sequence(seq)
    mock_cap_config.expects(:load).with(:string => recipe_1.body ).in_sequence(seq)

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    #
    # start

    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!
    remove_directory(@deployment.stage.project.capsize_project_name)

  end

  def test_handling_of_exceptions_during_command_execution
    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:load)
    mock_cap_config.stubs(:fetch).with(:scm)

    # vars
    mock_cap_config.stubs(:set)

    # roles
    mock_cap_config.stubs(:role)

    # interesting part, unexpected exception (e.g. non-SSH, non-Capistrano)
    mock_cap_config.expects(:find_and_execute_task).raises(RuntimeError)

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    #
    # start

    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!
    remove_directory(@deployment.stage.project.capsize_project_name)


    @deployment.reload
    assert_match(/RuntimeError/, @deployment.log)
  end

  def test_setting_of_project_and_stage_name
    # set project/stage names
    @project.name = "MySampleProject"
    @project.save!

    @stage.name = "MySample Stage 12"
    @stage.save!

    # delete all variables
    @project.configuration_parameters.delete_all
    @stage.configuration_parameters.delete_all

    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock

    mock_cap_config.stubs(:load)
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:find_and_execute_task)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:fetch).with(:scm)

    # roles
    mock_cap_config.stubs(:role)

    install_fake_set(mock_cap_config)

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    # run
    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!
    remove_directory(@deployment.stage.project.capsize_project_name)


    # check that the correct project/stage name was set
    assert_equal "my_sample_project", $vars_set[:capsize_project]
    assert_equal "my_sample_stage_12", $vars_set[:capsize_stage]
  end

  def test_reference_of_configuration_parameters
    @project.configuration_parameters.create!(:name => 'foo', :value => 'a nice value here, please!')
    @stage.configuration_parameters.create!(:name => 'using_foo', :value => 'Sir: #{foo}')
    @stage.configuration_parameters.create!(:name => 'bar', :value => '12')
    @stage.configuration_parameters.create!(:name => 'using_foo_and_bar', :value => '#{bar} #{foo}')

    mock_cap_config = prepare_config_mocks

    install_fake_set(mock_cap_config)

    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!
    remove_directory(@deployment.stage.project.capsize_project_name)


    assert_equal "Sir: a nice value here, please!", $vars_set[:using_foo]
    assert_equal "12 a nice value here, please!", $vars_set[:using_foo_and_bar]
  end

  def test_reference_of_random_methods
    Kernel.expects(:exit).never
    @project.configuration_parameters.create!(:name => 'foo', :value => '#{Kernel.exit}')

    mock_cap_config = prepare_config_mocks

    install_fake_set(mock_cap_config)

    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!
    remove_directory(@deployment.stage.project.capsize_project_name)


    assert_equal '#{Kernel.exit}', $vars_set[:foo]
  end

  def test_reference_of_configuration_parameters_in_prompt_config
    @project.configuration_parameters.create!(:name => 'foo', :value => 'a nice value here, please!')
    @stage.configuration_parameters.create!(:name => 'using_foo', :prompt_on_deploy => 1)

    mock_cap_config = prepare_config_mocks

    install_fake_set(mock_cap_config)

    deployment = Deployment.new
    deployment.stage = @stage
    deployment.task = 'deploy'
    deployment.description = 'bugfix'
    deployment.user = create_new_user
    deployment.roles << @stage.roles
    deployment.prompt_config = {:using_foo => '#{foo} 1234'}
    deployment.save!

    # run
    deployer = Capsize::Deployer.new(deployment)
    deployer.invoke_task!
    remove_directory(deployment.stage.project.capsize_project_name)

    assert_equal "a nice value here, please! 1234", $vars_set[:using_foo]
  end

  # test that we do not throw an exception if sudo is used
  def test_sudo_callback_behaviour
    # original Capistrano Config
    assert_not_nil Capistrano::Configuration.default_io_proc
    assert Capistrano::Configuration.default_io_proc.is_a?(Proc)

    # Capsize Config
    assert_not_nil Capsize::Configuration.default_io_proc
    assert Capsize::Configuration.default_io_proc.is_a?(Proc)
  end

  def test_ssh_options
    c = @project.configuration_parameters.build(
    :name => 'ssh_port',
    :value => '44'
    )
    c.save!


    deployer = Capsize::Deployer.new(@deployment)

    deployer.expects(:execute_requested_actions).returns(nil)
    deployer.stubs(:save_revision)
    deployer.invoke_task!
    remove_directory(@deployment.project.capsize_project_name)

  end

  def test_list_tasks
    d = Deployment.new
    d.stage = @stage
    deployer = Capsize::Deployer.new(d)

    assert_not_nil deployer.list_tasks
    assert_equal 25, deployer.list_tasks.size, deployer.list_tasks.map(&:fully_qualified_name).sort.inspect
    assert_equal 23, @stage.list_tasks.size # filter shell and invoke
    deployer.list_tasks.each{|t| assert t.is_a?(Capistrano::TaskDefinition) }

    # add a stage recipe
    recipe_body = <<-EOS
    namespace :foo do
      task :bar do
        run 'foobar'
      end
    end
    EOS
    recipe = create_new_recipe(:name => 'A new recipe', :body => recipe_body)
    @stage.recipes << recipe

    assert_equal 26, deployer.list_tasks.size
    assert_equal 24, @stage.list_tasks.size # filter shell and invoke
    assert_equal 1, deployer.list_tasks.delete_if{|t| t.fully_qualified_name != 'foo:bar'}.size
    assert_equal 1, @stage.list_tasks.delete_if{|t| t[:name] != 'foo:bar'}.size
  end

  def test_project_directory_is_created
    deployer = Capsize::Deployer.new(@deployment)

    assert !Dir.exists?(rooted("sample_project"))
    deployer.find_or_create_project_dir("sample_project")
    assert Dir.exists?(rooted("sample_project"))

    assert !Dir.exists?(rooted("#{@deployment.stage.project.capsize_project_name}"))
    deployer.invoke_task!
    assert Dir.exists?(rooted("#{@deployment.stage.project.capsize_project_name}"))

    remove_directory("sample_project")
    remove_directory(@deployment.stage.project.capsize_project_name)
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


  protected

  # mocks the Capistrano config so that it does not care about anything
  def prepare_config_mocks

    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock

    mock_cap_config.stubs(:load)
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:find_and_execute_task)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:fetch).with(:scm)

    # vars
    mock_cap_config.stubs(:set)

    # roles
    mock_cap_config.stubs(:role)

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    mock_cap_config
  end

  def install_fake_set(mock_cap_config)
    # override the configs set in order to let normal set operations happen
    $vars_set = {}
    def mock_cap_config.set(key, val=nil)
      $vars_set[key] = val
    end
  end

  def assert_correct_task_called(task_name)
    @deployment = create_new_deployment(:stage => @stage, :task => task_name)
    # prepare Mocks
    #

    # Logger stubing
    mock_cap_logger = mock
    mock_cap_logger.expects(:level=).with(3)

    # config stubbing
    mock_cap_config = mock
    mock_cap_config.stubs(:logger).returns(mock_cap_logger)
    mock_cap_config.stubs(:logger=)
    mock_cap_config.stubs(:load)
    mock_cap_config.stubs(:trigger)
    mock_cap_config.stubs(:[])
    mock_cap_config.stubs(:fetch).with(:scm)

    # vars
    mock_cap_config.stubs(:set)

    # roles
    mock_cap_config.stubs(:role)

    # now the interesting part, the task
    mock_cap_config.expects(:find_and_execute_task).with(task_name, {:after => :finish, :before => :start})

    # main mock install
    Capsize::Configuration.expects(:new).returns(mock_cap_config)

    # get things started
    deployer = Capsize::Deployer.new(@deployment)
    deployer.invoke_task!
    remove_directory(@deploymen.stage.project.capsize_project_name)
  end

  def remove_directory(project)
    FileUtils.rm_rf(rooted("#{project}"))
  end

end
