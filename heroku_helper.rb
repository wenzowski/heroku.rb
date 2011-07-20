require 'heroku'
require 'fog'
require 'git'
require 'json'

def new_s3_bucket(aws_credentials, app)
  storage = Fog::Storage.new(aws_credentials.merge(:provider => 'AWS'))
  storage.put_bucket(app)

  iam = Fog::AWS::IAM.new(aws_credentials)

  user_response = iam.create_user(app)
  key_response  = iam.create_access_key('UserName' => app)

  access_key_id     = key_response.body['AccessKey']['AccessKeyId']
  secret_access_key = key_response.body['AccessKey']['SecretAccessKey']
  arn               = user_response.body['User']['Arn']

  # Give the user the ability to manage their own keys.
  iam.put_user_policy(app, 'UserKeyPolicy', {
    'Statement' => [
      'Effect' => 'Allow',
      'Action' => 'iam:*AccessKey*',
      'Resource' => arn 
    ]
  })
  
  iam.put_user_policy(app, 'UserS3Policy', {
    'Statement' => [
      {   
        'Effect' => 'Allow',
        'Action' => ['s3:*'],
        'Resource' => [
          "arn:aws:s3:::#{app}",
          "arn:aws:s3:::#{app}/*"
        ]   
      }, {
        'Effect' => 'Deny',
        'Action' => ['s3:*'],
        'NotResource' => [
          "arn:aws:s3:::#{app}",
          "arn:aws:s3:::#{app}/*"
        ]   
      }   
    ]
  })
  
  bucket_credentials = {
    :aws_access_key_id => access_key_id,
    :aws_secret_access_key => secret_access_key
  }

  return bucket_credentials
end

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
  aws_credentials = {
    :aws_access_key_id => ENV['S3_KEY'],
    :aws_secret_access_key => ENV['S3_SECRET']
  }

  # Make sure the repo we want exists locally
  begin
    g = Git.open(options[:repo_dir])
  rescue
    g = Git.clone(options[:github_url], options[:github_repo], :path => options[:base_dir])
  end

  # Create s3 bucket for this app and install it. Required for Refinery.
  bucket_credentials = new_s3_bucket(aws_credentials, app)
  heroku_config_vars = {
    :S3_KEY => bucket_credentials[:aws_access_key_id],
    :S3_SECRET => bucket_credentials[:aws_secret_access_key],
    :S3_BUCKET => app
  }
  heroku.add_config_vars(app, heroku_config_vars)

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

def new_s3_bucket(aws_credentials, app)
  storage = Fog::Storage.new(aws_credentials.merge(:provider => 'AWS'))
  storage.put_bucket(app)

  iam = Fog::AWS::IAM.new(aws_credentials)

  user_response = iam.create_user(app)
  key_response  = iam.create_access_key('UserName' => app)

  access_key_id     = key_response.body['AccessKey']['AccessKeyId']
  secret_access_key = key_response.body['AccessKey']['SecretAccessKey']
  arn               = user_response.body['User']['Arn']

  # Give the user the ability to manage their own keys.
  iam.put_user_policy(app, 'UserKeyPolicy', {
    'Statement' => [
      'Effect' => 'Allow',
      'Action' => 'iam:*AccessKey*',
      'Resource' => arn 
    ]
  })
  
  iam.put_user_policy(app, 'UserS3Policy', {
    'Statement' => [
      {   
        'Effect' => 'Allow',
        'Action' => ['s3:*'],
        'Resource' => [
          "arn:aws:s3:::#{app}",
          "arn:aws:s3:::#{app}/*"
        ]   
      }, {
        'Effect' => 'Deny',
        'Action' => ['s3:*'],
        'NotResource' => [
          "arn:aws:s3:::#{app}",
          "arn:aws:s3:::#{app}/*"
        ]   
      }   
    ]
  })
  
  bucket_credentials = {
    :aws_access_key_id => access_key_id,
    :aws_secret_access_key => secret_access_key
  }

  return bucket_credentials
end