#!/usr/bin/env ruby

require 'slack-notifier'
require 'time'
require 'chef-api'
require 'json'
require 'active_support/inflector'

class ChefBot
  include ChefAPI::Resource

  attr_reader :stale_nodes_file
  attr_accessor :notifier

  def initialize
    @stale_nodes_file = ENV['CHEF_BOT_STALE_CACHE_FILENAME'] || 'stale.json'

    @icon_url = ENV['CHEF_BOT_ICON_URL'] || 'http://ops.evertrue.com.s3.amazonaws.com/public/chef_logo.png'

    # Make sure all of the necessary environment variables have been defined.
    validate_environment!

    ChefAPI.configure do |config|
      # The endpoint for the Chef Server. This can be an Open Source Chef Server,
      # Hosted Chef Server, or Enterprise Chef Server.
      config.endpoint = ENV['CHEF_SERVER_ENDPOINT']

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
      config.client = ENV['KNIFE_NODE_NAME']
      config.key    = ENV['KNIFE_CLIENT_KEY']

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

    notifier.channel = ENV['CHEF_BOT_CHANNEL']
    notifier.username = ENV['CHEF_BOT_NAME'] || 'Chef Bot'
  end

  def validate_environment!
    vars = %w(
      CHEF_SERVER_ENDPOINT
      KNIFE_NODE_NAME
      KNIFE_CLIENT_KEY
      CHEF_BOT_SLACK_HOOK
      CHEF_BOT_CHANNEL
    )
    undefined_vars = vars.reject { |var| ENV[var] }
    return if undefined_vars.empty?
    fail "Required variables are not defined: #{undefined_vars.join(' ')}"
  end

  def known_stale
    @known_stale ||= File.exist?(stale_nodes_file) ? JSON.parse(File.read(stale_nodes_file)) : []
  end

  def new_stale
    current_stale - known_stale
  end

  def freshened
    known_stale - current_stale
  end

  def current_stale
    @current_stale ||= begin
      timeout = (ENV['CHEF_BOT_STALE_TIME'] || 4800).to_i

      nodes = Search.query(
        :node,
        "ohai_time:[* TO #{Time.now.to_i - timeout}]",
        start: 1
      )
      nodes.rows.map { |result| return result['name'] }
    end
  end

  def save
    File.open(stale_nodes_file, 'w') { |f| f.write(current_stale.to_json) }
  end

  def update
    messages = []
    attachments = []

    # Nodes that just went stale
    if new_stale.any?
      attachments << generate_attachments(new_stale, 'warning')
      messages <<
        "#{new_stale.length} #{'node'.pluralize(new_stale.length)} " \
        'in your network have gone stale'
    end

    # Nodes that freshened
    if freshened.any?
      attachments << generate_attachments(freshened, 'good')
      messages <<
        "#{freshened.length} #{'node'.pluralize(freshened.length)} " \
        'in your network have freshened'
    end

    # Tag on a totals message to display the complete state of the nodes
    message <<
      "Currently #{current_stale.length} stale " \
      "#{'node'.pluralize(current_stale.length)}"

    # Send message to slack if there are any attachments (anything went stale or freshened)
    @notifier.ping message.join("\n"), attachments: attachments, icon_url: @icon_url if attachments.any?

    puts "[#{Time.now.utc.iso8601}] Stale Nodes: #{current_stale.join(', ')}" if current_stale.any?

    # Save the current list of stale nodes for next time
    save
  end

  def generate_attachments(nodes, color)
    {
      fallback: nodes.map { |fqdn| " - #{fqdn}" }.join("\n"),
      text: nodes.map { |fqdn| " - #{fqdn}" }.join("\n"),
      color: color
    }
  end
end

ChefBot.new.update
