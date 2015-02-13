module Capsize
  module Template
    module Base
      CONFIG = {
        :application => 'your_app_name',
        :deploy_to => '/path/to/deployment_base',
        :scm => ':git',
        :user => 'deployment_user(SSH login)',
        :repo_url => 'https://svn.example.com/project/trunk',
        :linked_files => '%w{}',
        :linked_dirs => '%w{}',
        :branch => 'master',
        :keep_releases => '5',
        :tmp_dir => '/tmp',
        :pty => 'false',
        :log_level => ':debug',
        :format => ':pretty'
      }.freeze

      DESC = <<-'EOS'
        Base template that the other templates use to inherit from.
        Defines basic Capistrano configuration parameters.
        Overrides no default Capistrano tasks.
      EOS

      TASKS =  <<-'EOS'
        # allocate a pty by default as some systems have problems without
        default_run_options[:pty] = true

        # set Net::SSH ssh options through normal variables
        # at the moment only one SSH key is supported as arrays are not
        # parsed correctly by Capsize::Deployer.type_cast (they end up as strings)
        [:ssh_port, :ssh_keys].each do |ssh_opt|
          if exists? ssh_opt
            logger.important("SSH options: setting #{ssh_opt} to: #{fetch(ssh_opt)}")
            ssh_options[ssh_opt.to_s.gsub(/ssh_/, '').to_sym] = fetch(ssh_opt)
          end
        end
      EOS
    end
  end
end
