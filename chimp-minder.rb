require 'active_support'
require 'gibbon'
require 'dotenv'

Dotenv.load

gb = Gibbon::API.new
gb.api_key = ENV["OVERRIDE_API_KEY"].empty? ? ENV["MAILCHIMP_API_KEY"] : ENV["OVERRIDE_API_KEY"].strip

from_list = gb.lists.list({:filters => {:list_name => ENV["FROM_LIST"]}})
from_list_id = from_list["data"][0]["id"]

to_list = gb.lists.list({:filters => {:list_name => ENV["TO_LIST"]}})
to_list_id = to_list["data"][0]["id"]

from_list_members = gb.lists.members({:id => from_list_id})["data"]

from_list_members.each do |member|
  
  merge_vars = ENV["MERGE_VARS"].split(',').inject({}) do |hash, value|
    hash[value.strip] = member["merges"][value.strip]
    hash
  end
    
  unless ENV["GUID_VAR"].strip.empty?
    merge_vars[ENV["GUID_VAR"].strip] = SecureRandom.urlsafe_base64(nil, false)
  end
  
  Gibbon::API.lists.subscribe({
    :id => to_list_id, 
    :email => {email: member["email"]}, 
    :email_type => "html", 
    :merge_vars => merge_vars, 
    :double_optin => false, 
    :update_existing => false, 
    :send_welcome => false
  })
  
  Gibbon::API.lists.unsubscribe({
    :id => from_list_id,
    :email => {email: member["email"]},
    :delete_member => true,
    :send_goodbye => false,
    :send_notify => false
  })

end
