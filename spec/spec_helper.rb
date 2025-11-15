require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end

require File.expand_path('../../app', __FILE__)
require 'rack/test'

ENV['RACK_ENV'] = 'test'

RSpec.configure do |config|
  config.include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

RSpec.configure do |config|
  config.before(:each) do
    header 'Host', 'localhost'
  end
end
