require 'active_support/all'
require 'active_support/secure_random'
require 'gibbon'
require 'dotenv'
require 'log4r'

Dotenv.load

log = Log4r::Logger.new("ChimpMinder")

if ENV["CONSOLE_ERRORS"] == "true"
  Log4r::StderrOutputter.new('console',
                            :level=>Log4r::FATAL)
  log.add('console')
end

if ENV["LOGFILE"].present?
  Log4r::FileOutputter.new('logfile',
                          :filename => ENV["LOGFILE"],
                          :trunc => false)
  log.add('logfile')
end

log.info "awakens at #{Time.now} for some heavy lifting!"
log.info "moving #{ENV["MERGE_VARS"]} #{ENV["GUID_VAR"]} from #{ENV["FROM_LIST"]} to #{ENV["TO_LIST"]}."

gb = Gibbon::API.new
gb.api_key = ENV["OVERRIDE_API_KEY"] || ENV["MAILCHIMP_API_KEY"]

log.info "Using API key: #{gb.api_key}"

begin
  from_list = gb.lists.list({:filters => {:list_name => ENV["FROM_LIST"]}})
  if from_list["total"] > 0
    from_list_id = from_list["data"][0]["id"]
    log.info "FROM_LIST \'#{ENV["FROM_LIST"]}\' loaded successfully."
  else
    log.fatal "FROM_LIST \'#{ENV["FROM_LIST"]}\' not found. Chimp Minder abort!"
    exit
  end

  to_list = gb.lists.list({:filters => {:list_name => ENV["TO_LIST"]}})
  if to_list["total"] > 0
    to_list_id = to_list["data"][0]["id"]
    log.info "TO_LIST \'#{ENV["TO_LIST"]}\' loaded successfully."
  else
    log.fatal "TO_LIST \'#{ENV["TO_LIST"]}\' not found. Chimp Minder abort!"
    exit
  end

  from_list_members = gb.lists.members({:id => from_list_id})["data"]

rescue Gibbon::MailChimpError => e
  log.fatal "MailChimp error #{e.code}: {#{e.message}. Chimp Minder abort!"
  exit
end

successfully_moved_count = 0

from_list_members.each do |member|

  merge_vars = ENV["MERGE_VARS"].split(',').inject({}) do |hash, value|
    hash[value.strip] = member["merges"][value.strip]
    hash
  end

  if ENV["GUID_VAR"].present?
    merge_vars[ENV["GUID_VAR"]] = SecureRandom.urlsafe_base64(nil, false)
  end

  begin
    gb.lists.subscribe({
      :id => to_list_id,
      :email => {email: member["email"]},
      :email_type => "html",
      :merge_vars => merge_vars,
      :double_optin => false,
      :update_existing => false,
      :send_welcome => false
    })

    gb.lists.unsubscribe({
      :id => from_list_id,
      :email => {email: member["email"]},
      :delete_member => true,
      :send_goodbye => false,
      :send_notify => false
    })

    successfully_moved_count += 1
    log.info "#{member["email"]} - moved successfully! (#{successfully_moved_count}/#{from_list_members.count})"

  rescue Gibbon::MailChimpError => e
    if e.code == 214
      log.warn "#{member["email"]} is already a member of #{ENV["TO_LIST"]}."

      if ENV["REMOVE_DUPES"] == "true"
        begin
          gb.lists.unsubscribe({
            :id => from_list_id,
            :email => {email: member["email"]},
            :delete_member => true,
            :send_goodbye => false,
            :send_notify => false
          })
          log.info "duplicate #{member["email"]} removed from #{ENV["FROM_LIST"]}."

        rescue Gibbon::MailChimpError => e
          log.warn "Couldn't remove #{member["email"]}. MailChimp error #{e.code}: #{e.message}."
        end
      end
    else
      log.warn "couldn't move #{member["email"]} due to MailChimp error #{e.code}: {#{e.message}}"
    end
  end

end

if successfully_moved_count > 0
  log.info "moved #{successfully_moved_count} of #{from_list_members.count} list members from #{ENV["FROM_LIST"]} to #{ENV["TO_LIST"]}."
else
  log.info "found no list members in #{ENV["FROM_LIST"]} to move."
end

log.info "is sleeping again as of #{Time.now}."
