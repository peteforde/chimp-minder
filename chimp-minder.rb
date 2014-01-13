require 'active_support'
require 'gibbon'
require 'dotenv'

Dotenv.load

gb = Gibbon::API.new
gb.api_key = ENV["OVERRIDE_API_KEY"].empty? ? ENV["MAILCHIMP_API_KEY"] : ENV["OVERRIDE_API_KEY"]

begin
  from_list_id = gb.lists.list({:filters => {:list_name => ENV["FROM_LIST"]}})["data"][0]["id"]
rescue Gibbon::MailChimpError => e
  # e.message
  # e.code
end

begin
  to_list_id = gb.lists.list({:filters => {:list_name => ENV["TO_LIST"]}})["data"][0]["id"]
rescue Gibbon::MailChimpError => e
end

begin
  from_list_members = gb.lists.members({:id => from_list_id})["data"]
rescue Gibbon::MailChimpError => e
end

from_list_members.each do |member|
  
  merge_vars = ENV["MERGE_VARS"].split(',').inject({}) do |hash, value|
    hash[value.strip] = member["merges"][value.strip]
    hash
  end
    
  unless ENV["GUID_VAR"].empty?
    merge_vars[ENV["GUID_VAR"]] = SecureRandom.urlsafe_base64(nil, false)
  end
  
  begin    
    Gibbon::API.lists.subscribe({
      :id => to_list_id, 
      :email => {email: member["email"]}, 
      :email_type => "html", 
      :merge_vars => merge_vars, 
      :double_optin => false, 
      :update_existing => false, 
      :send_welcome => false
    })
  rescue Gibbon::MailChimpError => e
  end
  
  begin
    Gibbon::API.lists.unsubscribe({
      :id => from_list_id,
      :email => {email: member["email"]},
      :delete_member => true,
      :send_goodbye => false,
      :send_notify => false
    })
  rescue Gibbon::MailChimpError => e
  end

end
