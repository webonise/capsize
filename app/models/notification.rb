class Notification < ActionMailer::Base
  
  @@capsize_sender_address = 'Capsize'
  
  def self.capsize_sender_address=(val)
    @@capsize_sender_address = val
  end

  def deployment(deployment, email)
    @subject    = "Deployment of #{deployment.stage.project.name}/#{deployment.stage.name} finished: #{deployment.status}"
    @body       = {:deployment => deployment}
    @recipients = email
    @from       = @@capsize_sender_address
    @sent_on    = Time.now
    @headers    = {}
  end
end
