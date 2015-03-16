module Capistrano
  module DSL
    module Stages
      def stages
        @@stages
      end

      def self.set_stages(stage)
        @@stages = [stage]
      end
    end
  end
end
