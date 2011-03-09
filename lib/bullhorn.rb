require 'net/http'
require 'uri'
require 'base64'
require 'json'
require 'cgi'
require 'digest/sha1'

class Bullhorn
  autoload :Plugin, "bullhorn/plugin"
  autoload :Sender, "bullhorn/sender"
  autoload :Backtrace, "bullhorn/backtrace"

  LANGUAGE    = "ruby"
  CLIENT_NAME = "bullhorn-ruby"
  VERSION = "0.1.0"

  URL = "http://www.bullhorn.it/api/v2/exception"

  FILTERING = %(['"]?\[?%s\]?['"]?=>?([^&\s]*))

  attr :filters
  attr :api_key
  attr :url
  attr :ignore_exceptions
  attr :show_code_context

  include Sender

  def initialize(app, options = {})
    @app               = app
    @api_key           = options[:api_key] || @@api_key || raise(ArgumentError, ":api_key is required")
    @filters           = Array(options[:filters] || @@filters)
    @url               = options[:url] || URL
    @ignore_exceptions = Array(options[:ignore_exceptions] || default_ignore_exceptions)
    @show_code_context = (options[:show_code_context].nil? ? (@@show_code_context || true) : options[:show_code_context])
  end

  def call(env)
    status, headers, body =
      begin
        @app.call(env)
      rescue Exception => ex
        unless ignore_exceptions.include?(ex.class)
          notify ex, env
        end

        raise ex
      end

    [status, headers, body]
  end

  class << self

    def api_key=(key)
      @@api_key = key
    end

    def api_key
      @@api_key
    end

    def filters=(val)
      @@filters = val
    end

    def filters
      @@filters
    end

    def show_code_context=(val)
      @@show_code_context
    end

    def show_code_context
      @@show_code_context
    end


    def notify_exception(exception)

      bt = Bullhorn::Backtrace.new(exception, :context => @show_code_context)

      post_options = {
        :api_key      => api_key,
        :message      => exception.message[0..100],
        :backtrace    => Bullhorn::Sender.serialize(bt.to_a),
        :env          => Bullhorn::Sender.serialize({}),
        :request_body => Bullhorn::Sender.serialize(""),
        :sha1         => Bullhorn::Sender.sha1(exception),
        # APIv2
        :language       => Bullhorn::LANGUAGE,
        :client_name    => Bullhorn::CLIENT_NAME,
        :client_version => Bullhorn::VERSION,
        :url            => "",
        :class          => exception.class.to_s
      }

      Net::HTTP.post_form(URI(Bullhorn::URL), post_options)
      
    end
  end
  

protected
  def default_ignore_exceptions
    [].tap do |exceptions|
      exceptions << ActiveRecord::RecordNotFound if defined? ActiveRecord
      exceptions << AbstractController::ActionNotFound if defined? AbstractController
      exceptions << ActionController::RoutingError if defined? ActionController
    end
  end
end
