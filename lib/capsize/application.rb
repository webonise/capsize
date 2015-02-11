module Capsize
  module Application
    def self.load_tasks
      Application.load_tasks_in_isolation do
        require 'capistrano/all'
        cap = Capistrano::Application.new
        Rake.application = cap
        cap.init
        cap.load_rakefile
        cap.tasks
      end
    end

    def self.load_tasks_in_isolation
      read, write = IO.pipe

      pid = fork do
        read.close
        result = yield
        write.puts result
        exit!(0)
      end

      write.close
      cap_tasks = []
      read.each_line { |task| cap_tasks << task }
      Process.wait(pid)
      cap_tasks
    end
  end
end
