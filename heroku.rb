# REMEMBER TO EXPORT THESE VARIABLES
#
# HEROKU_USER='username'
# HEROKU_PASSWORD='token'
# S3_KEY='key'
# S3_SECRET='secret'

require 'heroku'
require 'aws/s3'
require 'git'
require 'json'


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
options[:github_url]  = "git@github.com:#{options[:github_user]}/#{options[:github_repo]}"

heroku = Heroku::Client.new ENV['HEROKU_USER'], ENV['HEROKU_PASSWORD']

def create(heroku, options)
  timeout = 30
  name    = options[:appname].shift.downcase.strip rescue nil
  app     = heroku.create_request name, :stack => options[:stack]
  puts app

  begin
    Timeout::timeout(timeout) do
      loop do
        break if heroku.create_complete?(app)
        sleep 1
      end
    end

    options[:addons].each do |addon|
      heroku.install_addon(app, addon)
    end

    return app
  rescue Timeout::Error
    # PROPER error handling needed.
    puts "Timed Out! Check heroku info for status updates."
  end
end


def install(heroku, app, options)
  # Make sure the repo we want exists locally
  begin
    g = Git.open(options[:repo_dir])
  rescue
    g = Git.clone(options[:github_url], options[:github_repo], :path => options[:base_dir])
  end

  # Create s3 bucket for this app and install it. Required for Refinery.
  AWS::S3::Base.establish_connection!(:access_key_id => ENV['S3_KEY'], :secret_access_key => ENV['S3_SECRET'])
  AWS::S3::Bucket.create(app)
  heroku.add_config_vars app, {:S3_KEY => ENV['S3_KEY'], :S3_SECRET => ENV['S3_SECRET'], :S3_BUCKET => app}

  # Install the repo on our new Heroku app
  g.checkout options[:branch] # make sure we fork the right branch
  g.branch(app).create # fork and write to disk
  g.lib.remote_add app, "git@heroku.com:#{app}.git"
  g.push g.remote(app), "#{app}:master" # send to new app

  # Complete install
  heroku.rake app, "db:migrate"
  heroku.restart app

  # Add non-heroku url. Optional
  if options[:domain] then
    heroku.add_domain app, app+'.'+options[:domain]
    heroku.add_domain app, 'www.'+app+'.'+options[:domain]
  end

  # Configure Ranger
  @config_vars = heroku.config_vars(app)
  @ranger_api_key = ENV["RANGER_API_KEY"] || @config_vars["RANGER_API_KEY"]
  @ranger_app_id = ENV["RANGER_APP_ID"] || @config_vars["RANGER_APP_ID"]

  def add_watcher(email)
    resource = authenticated_resource("/apps/#{@ranger_app_id}/watchers.json")
    params = { :watcher => { :email => email }, :api_key => @ranger_api_key}
    resource.post(params)
  end

  def add_domain(url)
    resource = authenticated_resource("/apps/#{@ranger_app_id}/dependencies.json")
    params = { :dependency => { :name => "Website", :url => url, :check_every => "1" }, :api_key => @ranger_api_key}
    resource.post(params)
  end

  def authenticated_resource(path)
    host = "https://rangerapp.com/api/v1"
    RestClient::Resource.new("#{host}#{path}")
  end

  add_domain "http://#{app}.heroku.com"
  if options[:email] then
    add_watcher options[:email]
  end

end


app = create(heroku, options)
install(heroku, app, options)

