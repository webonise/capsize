module CapistranoExtensions
  @extensions = { "rvm" => "rvm",
                  "bundler" => "bundler",
                  "rails" => %w{rails/assets rails/migrations},
                  "rbenv" => "rbenv",
                  "composer" => "composer",
                  "symfony" => "symfony",
                  "npm" => "npm",
                  "laravel" => "laravel",
                  "chruby" => "chruby"
                }

  def self.available_extensions
    @extensions.values.flatten
  end

  def self.gems
    @extensions.keys
  end
end
