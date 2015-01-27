class ProjectConfiguration < ConfigurationParameter
  belongs_to :project
  
  validates_presence_of :project
  validates_uniqueness_of :name, :scope => :project_id
  
  # default templates for Projects
  def self.templates
    {
      'rails' => Capsize::Template::Rails,
      'mongrel_rails' => Capsize::Template::MongrelRails,
      'thin_rails' => Capsize::Template::ThinRails,   
      'mod_rails' => Capsize::Template::ModRails,
      'pure_file' => Capsize::Template::PureFile,
      'unicorn' => Capsize::Template::Unicorn
    }
  end
  
end
