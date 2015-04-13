# chef-bot
A Cron job that will check and report node staleness. Only supports slack as the messaging service

# Setup

As it stands right now, chef-bot should be run in a cron job on a machine with Ruby installed.

You should clone this repo to a place of your choosing.  

`git clone https://github.com/evertrue/chef-bot`

Then add this to your crontab using `crontab -e` or adding a crontab to `/etc/cron.d/` (slightly different format)
Example cron configuration

```
*/5 * * * * CHEF_SERVER_ENDPOINT="https://api.opscode.com/organizations/<your org>" CHEF_BOT_SLACK_HOOK="<Your Slack Hook>" KNIFE_NODE_NAME="username" KNIFE_CLIENT_KEY="/path/to/you.pem" CHEF_BOT_STALE_TIME=3600 CHEF_BOT_CHANNEL="#ops" /home/<username>/chef-bot/chef-bot.rb 
```

Let's break this down

**CHEF_SERVER_ENDPOINT** Is the api endpoint to the chef server.  Find this in your knife.rb

**CHEF_BOT_SLACK_HOOK** Is the Web Hook URL that you create with slack

**KNIFE_NODE_NAME** Find this in your knife.rb

**KNIFE_CLIENT_KEY** Find this in your knife.rb

**CHEF_BOT_CHANNEL** The slack channel to post to.  Example: "#ops"

**CHEF_BOT_STALE_TIME** Seconds since the last check in until a node is considered stale.  Default is 1 hour

The last part is the location of the `chef-bot.rb` script
