module Capsize
  module Template
    module Rails
      
      CONFIG = Capsize::Template::Base::CONFIG.dup.merge({
        :rails_env => 'production'
      }).freeze
      
      DESC = <<-'EOS'
        Basic Template for use in Ruby on Rails projects that use FastCGI
        for application servers. Uses default Capistrano tasks.
      EOS
      
      TASKS = Capsize::Template::Base::TASKS + <<-'EOS'
         
      EOS
    
    end
  end
end