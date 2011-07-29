require 'rubygems'
gem "opentox-ruby", "~> 2"
require 'opentox-ruby'

set :lock, true

helpers do
  def next_id
	  id = Dir["./public/*yaml"].collect{|f| File.basename(f.sub(/.yaml/,'')).to_i}.sort.last
	  id = 0 if id.nil?
	  id + 1
  end

  def uri(id)
    url_for "/#{id}", :full
  end

  # subjectid ist stored as memeber variable, not in params
  def load_dataset(id, params,content_type,input_data)

    @uri = uri id
    raise "store subject-id in dataset-object, not in params" if params.has_key?(:subjectid) and @subjectid==nil

    content_type = "application/rdf+xml" if content_type.nil?
    #dataset = OpenTox::Dataset.new(@uri, @subjectid) 
    dataset = OpenTox::Dataset.new(nil, @subjectid) 

    case content_type

    when /yaml/
      dataset.load_yaml(input_data)

    when /application\/rdf\+xml/
      dataset.load_rdfxml(input_data)
         
    when "chemical/x-mdl-sdfile"
      dataset.load_sdf(input_data)

    when /multipart\/form-data/ , "application/x-www-form-urlencoded" # file uploads

      case params[:file][:type]

      when "chemical/x-mdl-sdfile"
        dataset.load_sdf(input_data)

      when /yaml/
        dataset.load_yaml(params[:file][:tempfile].read)

      when "application/rdf+xml"
        dataset.load_rdfxml_file(params[:file][:tempfile])

      when "text/csv"
        #dataset = OpenTox::Dataset.new @uri
        dataset.load_csv(params[:file][:tempfile].read)
        dataset.add_metadata({
        DC.title => File.basename(params[:file][:filename],".csv"),
        OT.hasSource => File.basename(params[:file][:filename])
      })

      when /ms-excel/
        extension =  File.extname(params[:file][:filename])
        case extension
        when ".xls"
          xls = params[:file][:tempfile].path + ".xls"
          File.rename params[:file][:tempfile].path, xls # roo needs these endings
          book = Excel.new xls
        when ".xlsx"
          xlsx = params[:file][:tempfile].path + ".xlsx"
          File.rename params[:file][:tempfile].path, xlsx # roo needs these endings
          book = Excel.new xlsx
        else
          raise "#{params[:file][:filename]} is not a valid Excel input file."
        end
        dataset.load_spreadsheet(book)
        dataset.add_metadata({
          DC.title => File.basename(params[:file][:filename],extension),
          OT.hasSource => File.basename(params[:file][:filename])
        })

      else
        raise "MIME type \"#{params[:file][:type]}\" not supported."
      end

    else
      raise "MIME type \"#{content_type}\" not supported."
    end

    dataset.uri = @uri # update uri (also in metdata)
    dataset.features.keys.each { |f| dataset.features[f][OT.hasSource] = dataset.metadata[OT.hasSource] unless dataset.features[f][OT.hasSource]}
    File.open("public/#{@id}.yaml","w+"){|f| f.puts dataset.to_yaml}
  end
end

before do
  @accept = request.env['HTTP_ACCEPT']
  @accept = 'application/rdf+xml' if @accept == '*/*' or @accept == '' or @accept.nil?
  @id = request.path_info.match(/^\/\d+/)
  unless @id.nil?
    @id = @id.to_s.sub(/\//,'').to_i

    @uri = uri @id
    @yaml_file = "public/#{@id}.yaml"
    raise OpenTox::NotFoundError.new "Dataset #{@id} not found." unless File.exists? @yaml_file

    extension = File.extname(request.path_info)
    unless extension.empty?
     case extension
     when ".html"
       @accept = 'text/html'
     when ".yaml"
       @accept = 'application/x-yaml'
     when ".csv"
       @accept = 'text/csv'
     when ".rdfxml"
       @accept = 'application/rdf+xml'
     when ".xls"
       @accept = 'application/ms-excel'
     when ".sdf"
       @accept = 'chemical/x-mdl-sdfile'
     else
       raise OpenTox::NotFoundError.new "File format #{extension} not supported."
     end
    end
  end
  
  # make sure subjectid is not included in params, subjectid is set as member variable
  params.delete(:subjectid) 
end

## REST API

# Get a list of available datasets
# @return [text/uri-list] List of available datasets
get '/?' do
  uri_list = Dir["./public/*yaml"].collect{|f| File.basename(f.sub(/.yaml/,'')).to_i}.sort.collect{|n| uri n}.join("\n") + "\n" 
  case @accept
  when /html/
    response['Content-Type'] = 'text/html'
    OpenTox.text_to_html uri_list
  else
    response['Content-Type'] = 'text/uri-list'
    uri_list
  end
end

# Get a dataset representation
# @param [Header] Accept one of `application/rdf+xml, application-x-yaml, text/csv, application/ms-excel` (default application/rdf+xml)
# @return [application/rdf+xml, application-x-yaml, text/csv, application/ms-excel] Dataset representation
get '/:id' do
  
  case @accept

  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    file = "public/#{params[:id]}.rdfxml"
    unless File.exists? file # lazy rdfxml generation
      dataset = YAML.load_file(@yaml_file)
      File.open(file,"w+") { |f| f.puts dataset.to_rdfxml }
    end
    response['Content-Type'] = 'application/rdf+xml'
    File.read(file)

  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    File.read(@yaml_file)

   when /html/
    response['Content-Type'] = 'text/html'
    OpenTox.text_to_html File.read(@yaml_file) 

  when "text/csv"
    response['Content-Type'] = 'text/csv'
    YAML.load_file(@yaml_file).to_csv

  when /ms-excel/
    file = "public/#{params[:id]}.xls"
    YAML.load_file(@yaml_file).to_xls.write(file) unless File.exists? file # lazy xls generation
    response['Content-Type'] = 'application/ms-excel'
    File.open(file).read

  when /sdfile/
    response['Content-Type'] = 'chemical/x-mdl-sdfile'
    YAML.load_file(@yaml_file).to_sdf

  when /uri-list/
    response['Content-Type'] = 'text/uri-list'
    YAML.load_file(@yaml_file).to_urilist

  else
    raise OpenTox::NotFoundError.new "Content-type #{@accept} not supported."
  end
end

# Get metadata of the dataset
# @return [application/rdf+xml] Metadata OWL-DL
get '/:id/metadata' do

  metadata = YAML.load_file(@yaml_file).metadata
  
  case @accept
  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    response['Content-Type'] = 'application/rdf+xml'
    serializer = OpenTox::Serializer::Owl.new
    serializer.add_metadata url_for("/#{params[:id]}",:full), metadata
    serializer.to_rdfxml
  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    metadata.to_yaml
  end

end

# Get a dataset feature
# @param [Header] Accept one of `application/rdf+xml or application-x-yaml` (default application/rdf+xml)
# @return [application/rdf+xml,application/x-yaml] Feature metadata 
get %r{/(\d+)/feature/(.*)$} do |id,feature|

  @id = id
  @uri = uri @id
  @yaml_file = "public/#{@id}.yaml"
  feature_uri = url_for("/#{@id}/feature/#{URI.encode(feature)}",:full) # work around  racks internal uri decoding
  metadata = YAML.load_file(@yaml_file).features[feature_uri]
  
  case @accept
  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    response['Content-Type'] = 'application/rdf+xml'
    serializer = OpenTox::Serializer::Owl.new
    serializer.add_feature feature_uri, metadata
    serializer.to_rdfxml
  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    metadata.to_yaml
  end

end

# Get a list of all features
# @param [Header] Accept one of `application/rdf+xml, application-x-yaml, text/uri-list` (default application/rdf+xml)
# @return [application/rdf+xml, application-x-yaml, text/uri-list] Feature list 
get '/:id/features' do

  features = YAML.load_file(@yaml_file).features

  case @accept
  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    response['Content-Type'] = 'application/rdf+xml'
    serializer = OpenTox::Serializer::Owl.new
    features.each { |feature,metadata| serializer.add_feature feature, metadata }
    serializer.to_rdfxml
  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    features.to_yaml
  when "text/uri-list"
    response['Content-Type'] = 'text/uri-list'
    features.keys.join("\n") + "\n"
  end
end

# Get a list of all compounds
# @return [text/uri-list] Feature list 
get '/:id/compounds' do
  response['Content-Type'] = 'text/uri-list'
  YAML.load_file(@yaml_file).compounds.join("\n") + "\n"
end

# Create a new dataset.
#
# Posting without parameters creates and saves an empty dataset (with assigned URI).
# Posting with parameters creates and saves a new dataset.
# Data can be submitted either
# - in the message body with the appropriate Content-type header or
# - as file uploads with Content-type:multipart/form-data and a specified file type
# @example
#   curl -X POST -F "file=@training.csv;type=text/csv" http://webservices.in-silico.ch/dataset
# @param [Header] Content-type one of `application/x-yaml, application/rdf+xml, multipart/form-data/`
# @param [BODY] - string with data in selected Content-type
# @param [optional] file, for file uploads, Content-type should be multipart/form-data, please specify the file type `application/rdf+xml, application-x-yaml, text/csv, application/ms-excel` 
# @return [text/uri-list] Task URI or Dataset URI (empty datasets)
post '/?' do 
  
  response['Content-Type'] = 'text/uri-list'
  
  # it could be that the read function works only once!, store in varible
  input_data = request.env["rack.input"].read
  @id = next_id
  @uri = uri @id
  @yaml_file = "public/#{@id}.yaml"
  if params.size == 0 and input_data.size==0
    File.open(@yaml_file,"w+"){|f| f.puts OpenTox::Dataset.new(@uri).to_yaml}
    OpenTox::Authorization.check_policy(@uri, @subjectid) if File.exists? @yaml_file
    @uri
  else
    task = OpenTox::Task.create("Converting and saving dataset ", @uri) do 
      load_dataset @id, params, request.content_type, input_data 
      OpenTox::Authorization.check_policy(@uri, @subjectid) if File.exists? @yaml_file
      @uri
    end
    raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
    halt 202,task.uri+"\n"
  end
end

# Save a dataset, will overwrite all existing data
#
# Data can be submitted either
# - in the message body with the appropriate Content-type header or
# - as file uploads with Content-type:multipart/form-data and a specified file type
# @example
#   curl -X POST -F "file=@training.csv;type=text/csv" http://webservices.in-silico.ch/dataset/1
# @param [Header] Content-type one of `application/x-yaml, application/rdf+xml, multipart/form-data/`
# @param [BODY] - string with data in selected Content-type
# @param [optional] file, for file uploads, Content-type should be multipart/form-data, please specify the file type `application/rdf+xml, application-x-yaml, text/csv, application/ms-excel` 
# @return [text/uri-list] Task ID 
post '/:id' do 
  LOGGER.debug @uri
  response['Content-Type'] = 'text/uri-list'
  task = OpenTox::Task.create("Converting and saving dataset ", @uri) do 
    FileUtils.rm Dir["public/#{@id}.*"]
    load_dataset @id, params, request.content_type, request.env["rack.input"].read 
    @uri
  end
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end

# Delete a dataset
# @return [text/plain] Status message
delete '/:id' do
  LOGGER.debug "deleting dataset with id "+@id.to_s
  begin
    FileUtils.rm Dir["public/#{@id}.*"]
    if @subjectid and !File.exists? @yaml_file and @uri
      begin
        res = OpenTox::Authorization.delete_policies_from_uri(@uri, @subjectid)
        LOGGER.debug "Policy deleted for Dataset URI: #{@uri} with result: #{res}"
      rescue
        LOGGER.warn "Policy delete error for Dataset URI: #{@uri}"
      end
    end
    response['Content-Type'] = 'text/plain'
    "Dataset #{@id} deleted."
  rescue
    raise OpenTox::NotFoundError.new "Dataset #{@id} does not exist."
  end
end

# Delete all datasets
# @return [text/plain] Status message
delete '/?' do
  FileUtils.rm Dir["public/*.rdfxml"]
  FileUtils.rm Dir["public/*.xls"]
  FileUtils.rm Dir["public/*.yaml"]
  response['Content-Type'] = 'text/plain'
  "All datasets deleted."
end
