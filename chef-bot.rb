#!/usr/bin/env ruby

require 'slack-notifier'
require 'time'
require 'chef-api'
require 'json'

include ChefAPI::Resource

filename = 'stale.json'
icon_url = 'http://ops.evertrue.com.s3.amazonaws.com/public/chef_logo.png'
ChefAPI.configure do |config|
  # The endpoint for the Chef Server. This can be an Open Source Chef Server,
  # Hosted Chef Server, or Enterprise Chef Server.
  config.endpoint = "#{ENV['CHEF_SERVER_ENDPOINT']}"

  # ChefAPI will try to determine if you are running on an Enterprise Chef
  # Server or Open Source Chef depending on the URL you provide for the
  # +endpoint+ attribute. However, it may be incorrect. If is seems like the
  # generated schema does not match the response from the server, it is
  # possible this value was calculated incorrectly. Thus, you should set it
  # manually. Possible values are +:enterprise+ and +:open_source+.
  config.flavor = :enterprise

  # The client and key must also be specified (unless you are running Chef Zero
  # in no-authentication mode). The +key+ attribute may be the raw private key,
  # the path to the private key on disk, or an +OpenSSLL::PKey+ object.
  config.client = "#{ENV['KNIFE_NODE_NAME']}"
  config.key    = "#{ENV['KNIFE_CLIENT_KEY']}"

  # If you are running your own Chef Server with a custom SSL certificate, you
  # will need to specify the path to a pem file with your custom certificates
  # and ChefAPI will wire everything up correctly. (NOTE: it must be a valid
  # PEM file).
  # config.ssl_pem_file = '/path/to/my.pem'

  # If you would like to be vulnerable to MITM attacks, you can also turn off
  # SSL verification. Despite what Internet blog posts may suggest, you should
  # exhaust other methods before disabling SSL verification. ChefAPI will emit
  # a warning message for every request issued with SSL verification disabled.
  # config.ssl_verify = false

  # If you are behind a proxy, Chef API can run requests through the proxy as
  # well. Just set the following configuration parameters as needed.
  # config.proxy_username = 'user'
  # config.proxy_password = 'password'
  # config.proxy_address  = 'my.proxy.server' # or 10.0.0.50
  # config.proxy_port     = '8080'
end

notifier = Slack::Notifier.new ENV['CHEF_BOT_SLACK_HOOK']

notifier.channel = ENV['CHEF_BOT_CHANNEL']
notifier.username = ENV['CHEF_BOT_NAME'] ||= 'Chef Bot'

if ENV['CHEF_BOT_STALE_TIME']
  timeout = ENV['CHEF_BOT_STALE_TIME'].to_i
else
  timeout = 3600
end

stale = Search.query(:node, "ohai_time:[* TO #{Time.now.to_i - timeout}]", start: 1)

if File.exist?(filename)
  file = File.open(filename, 'r')
  known = JSON.parse(file.read)
  file.close
else
  known = []
end

attachments = []
new_known = []
message = ''
if stale.rows.length
  stale.rows.each do |result|
    new_known << result['name']
  end

  if (new_known - known).any?
    attachments << {
      fallback: (new_known - known).map { |fqdn| " - #{fqdn}" }.join("\n"),
      text: (new_known - known).map { |fqdn| " - #{fqdn}" }.join("\n"),
      color: 'warning'
    }
    hours = (timeout / 3600).floor
    if (known - new_known).length == 1
      message += "1 node in your network hasn't checked in in the last #{hours} hours\n"
    else
      message += "#{new_known.length} nodes in you network haven't checked in in the last #{hours} hours\n"
    end
  end
  if (known - new_known).any?
    attachments << {
      fallback: (known - new_known).map { |fqdn| " - #{fqdn}" }.join("\n"),
      text: (known - new_known).map { |fqdn| " - #{fqdn}" }.join("\n"),
      color: 'good'
    }
    if (known - new_known).length == 1
      message += "1 node in your network has freshened.\n"
    else
      message += "#{new_known.length} nodes in you network have freshened\n"
    end
  end
  notifier.ping message, attachments: attachments, icon_url: icon_url if attachments.any?
end

file = File.open(filename, 'w')
JSON.dump(new_known, file)
file.close

puts "[#{DateTime.now}] Stale Nodes: #{new_known}"
