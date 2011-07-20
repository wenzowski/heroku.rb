# REMEMBER TO EXPORT THESE VARIABLES
#
# HEROKU_USER='username'
# HEROKU_PASSWORD='token'
# S3_KEY='key'
# S3_SECRET='secret'
# 
# REMEMBER TO CONFIGURE CORRESPONDING SSH KEYS FOR HEROKU
# ~/.ssh/id_rsa
# ~/.ssh/id_rsa.pub

require 'heroku'
require_relative 'heroku_helper'

options = {
  :branch       => 'heroku',            # default branch
  :domain       => nil,                 # alternate domain
  :email        => nil,                 # for keepalive messages
  :github_user  => 'wenzowski',         # user that published github repo
  :github_repo  => 'refinerycms',       # github repo
  :base_dir     => '/tmp',              # writeable dir
  :appname      => nil,                 # name of app to be created, nil for default name
  :stack        => 'bamboo-mri-1.9.2',
  :addons       => ['memcache:5mb', 'custom_domains:basic', 'pgbackups:basic', 'ranger:test', 'newrelic'],
}
options[:repo_dir]    = options[:base_dir]+'/'+options[:github_repo]
options[:github_url]  = "git@github.com:#{options[:github_user]}/#{options[:github_repo]}.git"


heroku = Heroku::Client.new ENV['HEROKU_USER'], ENV['HEROKU_PASSWORD']
app = create(heroku, options)
install(heroku, app, options)
