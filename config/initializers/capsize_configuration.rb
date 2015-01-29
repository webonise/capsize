if CapsizeConfig[:authentication_method] == :cas
  cas_options = YAML::load_file(Rails.root.to_s+'/config/cas.yml')
  CASClient::Frameworks::Rails::Filter.configure(cas_options[Rails.env])
end

WEBISTRANO_VERSION = '1.5 - JS 1.0'

ActionMailer::Base.delivery_method = CapsizeConfig[:smtp_delivery_method] 
ActionMailer::Base.smtp_settings = CapsizeConfig[:smtp_settings] 

Notification.capsize_sender_address = CapsizeConfig[:capsize_sender_address]