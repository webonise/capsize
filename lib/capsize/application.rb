module Capsize
  module Application
    def load_tasks
      output = run_in_isolation do
        require 'capistrano/all'
        cap = Capistrano::Application.new
        Rake.application = cap
        cap.init
        cap.load_rakefile
        cap.tasks
      end
      cap_tasks = []
      output.each_line { |task| cap_tasks << task }
      cap_tasks.map { |task| task.gsub("\n", '') }
    end

    def run_in_isolation
      read, write = IO.pipe

      pid = fork do
        read.close
        write.puts yield
        exit!(0)
      end
      write.close

      Process.wait(pid)
      read.read
    end
  end
end
