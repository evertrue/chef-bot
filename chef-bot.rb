#!/usr/bin/env ruby

require 'slack-notifier'
require 'time'
require 'chef-api'
require 'json'

class Chef_Bot

  include ChefAPI::Resource

  def initialize
    @attachments = []
    @message = ''
    @icon_url = ENV['CHEF_BOT_ICON_URL'] || 'http://ops.evertrue.com.s3.amazonaws.com/public/chef_logo.png'
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

    @notifier = Slack::Notifier.new ENV['CHEF_BOT_SLACK_HOOK']

    @notifier.channel = ENV['CHEF_BOT_CHANNEL']
    @notifier.username = ENV['CHEF_BOT_NAME'] ||= 'Chef Bot'
  end

  def pluralize(n, singular, plural)
    if n == 1
      singular
    else
      plural
    end
  end

  def load_saved(filename)
    if File.exist?(filename)
      file = File.open(filename, 'r')
      @known_stale = JSON.parse(file.read)
      file.close
    else
      @known_stale = []
    end
  end

  def save(filename) 
    file = File.open(filename, 'w')
    JSON.dump(@current_stale, file)
    file.close
  end

  def query
    timeout = (ENV['CHEF_BOT_STALE_TIME'] || 4800).to_i

    nodes = Search.query(:node, "ohai_time:[* TO #{Time.now.to_i - timeout}]", start: 1)
    @current_stale = nodes.rows.map { |result| return result['name'] }
  end

  def update
    filename = 'stale.json'

    query()    
    load_saved(filename)

    # Nodes that just went stale
    new_stale = (@current_stale - @known_stale)
    generate_attachments(new_stale, 'warning', 'in your network just went stale')

    # Nodes that freshened
    old_stale = (@known_stale - @current_stale)
    generate_attachments(old_stale, 'good', 'in your network have freshened')

    # Tag on a totals message to display the complete state of the nodes
    @message += "There #{pluralize(current_stale.length, 'is', 'are')} currently #{current_stale.length} stale #{pluralize(current_stale.length, 'node', 'nodes')}"

    # Send message to slack if there are any attachments (anything went stale or freshened)
    @notifier.ping @message, attachments: @attachments, icon_url: @icon_url if @attachments.any?

    # Save the current list of stale nodes for next time

    puts "[#{DateTime.now}] Stale Nodes: #{@current_stale}"

    save(filename)
  end

  def generate_attachments(nodes, color, suffix)
    if nodes.any?
      @attachments << {
        fallback: nodes.map { |fqdn| " - #{fqdn}" }.join("\n"),
        text: nodes.map { |fqdn| " - #{fqdn}" }.join("\n"),
        color: color
      }
      @message += "#{nodes.length} #{pluralize(nodes.length, 'node', 'nodes')} #{suffix}\n"
    end
  end
end

Chef_Bot.new.update
