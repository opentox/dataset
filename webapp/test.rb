#for testing the error handling

module OpenTox
  class Application < Service
    
    post '/dataset/test/error_in_task/?' do
      task = OpenTox::Task.create($task[:uri],@subjectid,{ RDF::DC.description => "error_in_task"}) do |task|
        sleep 2
        internal_server_error "error_in_task_message"      
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri.to_s+"\n"
    end

  end
end