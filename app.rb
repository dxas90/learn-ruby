# encoding: UTF-8
require 'rubygems'
require 'sinatra'
require 'json'
require 'time'
require 'logger'

# Configure logger
logger = Logger.new(STDOUT)
logger.level = ENV['RACK_ENV'] == 'test' ? Logger::ERROR : Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{severity}] #{datetime.utc.iso8601} #{msg}\n"
end

# Make logger available to Sinatra
set :logger, logger

# Application metadata
APP_INFO = {
  name: 'learn-ruby',
  version: ENV['APP_VERSION'] || '0.0.1',
  environment: ENV['RACK_ENV'] || 'development',
  timestamp: Time.now.utc.iso8601
}.freeze

# Configure Sinatra
set :port, ENV['PORT'] || 4567
set :bind, ENV['HOST'] || '0.0.0.0'
set :public_folder, 'static'
set :logging, false  # Disable Sinatra's default logging (we handle it in before filter)

# Optional Prometheus client + OpenTelemetry initialization (best-effort)
begin
  require 'prometheus/client'
  require 'prometheus/client/formats/text'
  PROM_REGISTRY = Prometheus::Client.registry
  # Guard metric construction in case of gem API incompatibility
  begin
    # The prometheus-client gem changed its constructor to expect a docstring keyword
    # Use the keyword form if available to support newer gem versions.
    begin
      HTTP_REQUESTS = Prometheus::Client::Counter.new(:http_requests_total, docstring: 'Total HTTP requests', labels: [:method, :path, :status])
    rescue ArgumentError
      # Fallback to positional arg for older gem versions
      HTTP_REQUESTS = Prometheus::Client::Counter.new(:http_requests_total, 'Total HTTP requests', labels: [:method, :path, :status])
    end
    begin
      HTTP_REQUEST_DURATION = Prometheus::Client::Histogram.new(:http_request_duration_seconds, docstring: 'HTTP request duration (s)', labels: [:method, :path, :status])
    rescue ArgumentError
      HTTP_REQUEST_DURATION = Prometheus::Client::Histogram.new(:http_request_duration_seconds, 'HTTP request duration (s)', labels: [:method, :path, :status])
    end
    PROM_REGISTRY.register(HTTP_REQUESTS) rescue nil
    PROM_REGISTRY.register(HTTP_REQUEST_DURATION) rescue nil
    settings.logger.info '[INFO] Prometheus client initialized'
  rescue StandardError => e
    # If metric constructor fails (gem API mismatch), disable metrics gracefully
    PRI = e
    PROM_REGISTRY = nil
    HTTP_REQUESTS = nil
    settings.logger.info "[INFO] Prometheus client present but failed to initialize metrics: #{e.message}"
  end
rescue LoadError
  PROM_REGISTRY = nil
  HTTP_REQUESTS = nil
  settings.logger.info '[INFO] Prometheus client not installed; /metrics disabled'
end

begin
  if ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
    require 'opentelemetry/sdk'
    require 'opentelemetry/exporter/otlp'
    OpenTelemetry::SDK.configure do |c|
      c.service_name = 'learn-ruby'
      # Use default configuration where possible; exporter will pick env vars
      c.use_all
    end
    settings.logger.info '[INFO] OpenTelemetry configured'
  end
rescue LoadError => e
  settings.logger.info "[INFO] OpenTelemetry gems missing or failed to init: #{e.message}"
rescue => e
  settings.logger.info "[INFO] OpenTelemetry init error: #{e.message}"
end

# Disable Rack::Protection in test environment to avoid Rack::Test 403 issues
configure :test do
  disable :protection
end

# Middleware for logging (skip in test environment)
before do
  if ENV['RACK_ENV'] != 'test'
    user_agent = request.user_agent || 'Unknown'
    settings.logger.info "#{request.request_method} #{request.path} - User-Agent: #{user_agent}"
    # increment prometheus counter if present
    begin
      if defined?(HTTP_REQUESTS) && HTTP_REQUESTS
        status_label = (response.status || 200).to_s
        HTTP_REQUESTS.increment(labels: { method: request.request_method, path: request.path, status: status_label })
      end
    rescue => _e
      # ignore metric errors
    end
  end
end

# Security headers middleware
after do
  headers['X-Content-Type-Options'] = 'nosniff'
  headers['X-Frame-Options'] = 'DENY'
  headers['X-XSS-Protection'] = '1; mode=block'
  headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
  headers['Content-Security-Policy'] = "default-src 'self'"

  # CORS headers
  headers['Access-Control-Allow-Origin'] = ENV['CORS_ORIGIN'] || '*'
  headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
  headers['Access-Control-Allow-Headers'] = 'Content-Type'
end

# Helper method to get system info
def get_system_info
  require 'etc'

  memory_info = {}
  cpu_info = {}

  # Try to get memory info
  begin
    if File.exist?('/proc/meminfo')
      meminfo = File.read('/proc/meminfo')
      if meminfo =~ /MemTotal:\s+(\d+)/
        memory_info[:total] = $1.to_i * 1024
      end
      if meminfo =~ /MemFree:\s+(\d+)/
        memory_info[:free] = $1.to_i * 1024
      end
      if meminfo =~ /MemAvailable:\s+(\d+)/
        memory_info[:available] = $1.to_i * 1024
      end
      if memory_info[:total] && memory_info[:available]
        memory_info[:used] = memory_info[:total] - memory_info[:available]
        memory_info[:percent] = ((memory_info[:used].to_f / memory_info[:total]) * 100).round(2)
      end
    end
  rescue => e
    memory_info[:error] = e.message
  end

  # Get CPU info
  begin
    cpu_info[:count] = Etc.nprocessors
  rescue
    cpu_info[:count] = 1
  end

  {
    memory: memory_info,
    cpu: cpu_info
  }
end

# Helper method to get process info
def get_process_info
  uptime = 0
  begin
    # Try to get process start time
    stat_file = "/proc/#{Process.pid}/stat"
    if File.exist?(stat_file)
      stat_data = File.read(stat_file).split
      clock_ticks = 100.0 # Usually 100 on Linux
      boot_time = File.read('/proc/uptime').split[0].to_f
      start_time = stat_data[21].to_i / clock_ticks
      uptime = boot_time - start_time + Time.now.to_f - boot_time
    end
  rescue => e
    uptime = 0
  end

  {
    uptime: uptime,
    pid: Process.pid
  }
end

# Error handlers
not_found do
  content_type :json
  status 404
  {
    error: true,
    message: 'Resource not found',
    statusCode: 404,
    timestamp: Time.now.utc.iso8601
  }.to_json
end

error do
  content_type :json
  status 500
  error_details = ENV['RACK_ENV'] != 'production' ? env['sinatra.error'].message : nil
  {
    error: true,
    message: 'Internal Server Error',
    statusCode: 500,
    timestamp: Time.now.utc.iso8601,
    details: error_details
  }.to_json
end

# Route: Welcome page
get '/' do
  content_type :json
  welcome_data = {
    message: 'Welcome to learn-ruby API',
    description: 'A simple Sinatra microservice for learning and demonstration',
    documentation: {
      swagger: nil,
      postman: nil
    },
    links: {
      repository: 'https://github.com/dxas90/learn-ruby',
      issues: 'https://github.com/dxas90/learn-ruby/issues'
    },
    endpoints: [
      {
        path: '/',
        method: 'GET',
        description: 'API welcome and documentation'
      },
      {
        path: '/ping',
        method: 'GET',
        description: 'Simple ping-pong response'
      },
      {
        path: '/healthz',
        method: 'GET',
        description: 'Health check endpoint'
      },
      {
        path: '/info',
        method: 'GET',
        description: 'Application and system information'
      },
      {
        path: '/version',
        method: 'GET',
        description: 'Application version information'
      },
      {
        path: '/echo',
        method: 'POST',
        description: 'Echo back the request body'
      },
      {
        path: '/metrics',
        method: 'GET',
        description: 'Prometheus metrics endpoint'
      }
    ]
  }

  {
    success: true,
    data: welcome_data,
    timestamp: Time.now.utc.iso8601
  }.to_json
end

# Route: Ping
get '/ping' do
  content_type :text
  'pong'
end

# Route: Health check
get '/healthz' do
  content_type :json

  process_info = get_process_info
  system_info = get_system_info

  health_data = {
    status: 'healthy',
    uptime: process_info[:uptime],
    timestamp: Time.now.utc.iso8601,
    memory: system_info[:memory],
    version: APP_INFO[:version],
    environment: APP_INFO[:environment]
  }

  {
    success: true,
    data: health_data,
    timestamp: Time.now.utc.iso8601
  }.to_json
end

# Route: Application info
get '/info' do
  content_type :json

  process_info = get_process_info
  system_info = get_system_info

  info_data = {
    application: APP_INFO,
    system: {
      platform: RUBY_PLATFORM,
      ruby_version: RUBY_VERSION,
      uptime: process_info[:uptime],
      memory: system_info[:memory],
      cpu: system_info[:cpu]
    },
    environment: {
      rack_env: ENV['RACK_ENV'] || 'development',
      port: ENV['PORT'] || '4567',
      host: ENV['HOST'] || '0.0.0.0'
    }
  }

  {
    success: true,
    data: info_data,
    timestamp: Time.now.utc.iso8601
  }.to_json
end

# Route: Version
get '/version' do
  content_type :json

  {
    success: true,
    data: {
      version: APP_INFO[:version],
      name: APP_INFO[:name],
      environment: APP_INFO[:environment]
    },
    timestamp: Time.now.utc.iso8601
  }.to_json
end

# Route: Echo (for testing POST requests)
post '/echo' do
  content_type :json

  begin
    request.body.rewind
    body_content = request.body.read
    data = body_content.empty? ? {} : JSON.parse(body_content)

    {
      success: true,
      data: {
        echo: data,
        headers: request.env.select { |k, v| k.start_with?('HTTP_') }.transform_keys { |k| k.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-') },
        method: request.request_method
      },
      timestamp: Time.now.utc.iso8601
    }.to_json
  rescue JSON::ParserError
    status 400
    {
      error: true,
      message: 'Invalid JSON',
      statusCode: 400,
      timestamp: Time.now.utc.iso8601
    }.to_json
  end
end

# Handle OPTIONS for CORS preflight
options '*' do
  200
end

not_found do
  'This is nowhere to be found.'
end

# Prometheus metrics endpoint
get '/metrics' do
  if PROM_REGISTRY
    content_type Prometheus::Client::Formats::Text::CONTENT_TYPE
    Prometheus::Client::Formats::Text.marshal(PROM_REGISTRY)
  else
    status 204
    ''
  end
end
