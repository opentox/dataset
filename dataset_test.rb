require "rubygems"
require "sinatra"
before {
  request.env['HTTP_HOST']="local-ot/dataset"
  request.env["REQUEST_URI"]=request.env["PATH_INFO"]
}

require "opentox-ruby"
ENV['RACK_ENV'] = 'test'
require 'application.rb'
require 'test/unit'
require 'rack/test'
LOGGER = Logger.new(STDOUT)
LOGGER.datetime_format = "%Y-%m-%d %H:%M:%S "
  
module Sinatra
  
  set :raise_errors, false
  set :show_exceptions, false

  module UrlForHelper
    BASE = "http://local-ot/dataset"
    def url_for url_fragment, mode=:path_only
      case mode
      when :path_only
        raise "not impl"
      when :full
      end
      "#{BASE}#{url_fragment}"
    end
  end
end

class DatasetTest < Test::Unit::TestCase
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end
  
  def test_sth
    
   begin
    
     #http://local-ot/dataset/452
     #http://local-ot/dataset/453
     
     get '/504',nil,'HTTP_ACCEPT' => "text/arff"
     puts last_response.body
     
     #delete '/cleanup'
     #puts last_response.body
    
   rescue => ex
     rep = OpenTox::ErrorReport.create(ex, "")
     puts rep.to_yaml
   end 
    
  end
  
      # see test_util.rb
  def wait_for_task(uri)
      if uri.task_uri?
        task = OpenTox::Task.find(uri)
        task.wait_for_completion
        raise "task failed: "+uri.to_s if task.error?
        uri = task.result_uri
      end
      return uri
    end
  
  
  
end