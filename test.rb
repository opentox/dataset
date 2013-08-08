#ATTENTION: for testing the error handling in test/task.rb, CODE_LINES are important

module OpenTox
  class Application < Service
    
    post '/dataset/test/error_in_task/?' do
      task = OpenTox::Task.run("error_in_task", @uri) do |task|
        sleep 1
        bad_request_error "bad_request_error_in_task"      
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri.to_s+"\n"
    end
    
    get '/dataset/test/plain_error/?' do
      bad_request_error "plain_bad_request_error"      
    end
    
    get '/dataset/test/plain_no_ot_error/?' do
      nil.no_method_for_nil
    end
  end
end
