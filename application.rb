ENV["JAVA_HOME"] = "/usr/lib/jvm/java-6-sun" unless ENV["JAVA_HOME"]
ENV["JOELIB2"] = File.join File.expand_path(File.dirname(__FILE__)),"java"
deps = []
deps << "#{ENV["JAVA_HOME"]}/lib/tools.jar"
deps << "#{ENV["JAVA_HOME"]}/lib/classes.jar"
deps << "#{ENV["JOELIB2"]}"
jars = Dir[ENV["JOELIB2"]+"/*.jar"].collect {|f| File.expand_path(f) }
deps = deps + jars
ENV["CLASSPATH"] = deps.join(":")


require 'rubygems'
gem "opentox-ruby", "~> 3"
require 'opentox-ruby'
require 'profiler'
require 'rjb'

set :lock, true

@@datadir = "data"

helpers do
  def next_id
	  id = Dir["./#{@@datadir}/*json"].collect{|f| File.basename(f.sub(/.json/,'')).to_i}.sort.last
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
    dataset = OpenTox::Dataset.new(nil, @subjectid) 

    case content_type

    when /yaml/
      dataset.load_yaml(input_data)

    when /json/
      dataset.load_json(input_data)

    when /application\/rdf\+xml/
      dataset.load_rdfxml(input_data, @subjectid)
         
    when "chemical/x-mdl-sdfile"
      dataset.load_sdf(input_data, @subjectid)

    when /multipart\/form-data/ , "application/x-www-form-urlencoded" # file uploads

      case params[:file][:type]

      when "chemical/x-mdl-sdfile"
        dataset.load_sdf(input_data, @subjectid)

      when /json/
        dataset.load_json(params[:file][:tempfile].read)

      when /yaml/
        dataset.load_yaml(params[:file][:tempfile].read)

      when "application/rdf+xml"
        dataset.load_rdfxml_file(params[:file][:tempfile], @subjectid)

      when "text/csv"
        dataset.load_csv(params[:file][:tempfile].read, @subjectid)
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
        dataset.load_spreadsheet(book, @subjectid)
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
    File.open("#{@@datadir}/#{@id}.json","w+"){|f| f.puts dataset.to_json}
  end
end

before do

  @accept = request.env['HTTP_ACCEPT']
  @accept = 'application/rdf+xml' if @accept == '*/*' or @accept == '' or @accept.nil?
  @id = request.path_info.match(/^\/\d+/)
  unless @id.nil?
    @id = @id.to_s.sub(/\//,'').to_i

    @uri = uri @id
    @json_file = "#{@@datadir}/#{@id}.json"
    raise OpenTox::NotFoundError.new "Dataset #{@id} not found." unless File.exists? @json_file

    extension = File.extname(request.path_info)
    unless extension.empty?
     case extension
     when ".html"
       @accept = 'text/html'
     when ".json"
       @accept = 'application/json'
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
  uri_list = Dir["./#{@@datadir}/*json"].collect{|f| File.basename(f.sub(/.json/,'')).to_i}.sort.collect{|n| uri n}.join("\n") + "\n" 
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
    file = "#{@@datadir}/#{params[:id]}.rdfxml"
    unless File.exists? file # lazy rdfxml generation
      dataset = OpenTox::Dataset.from_json File.read(@json_file)
      File.open(file,"w+") { |f| f.puts dataset.to_rdfxml }
    end
    send_file file, :type => 'application/rdf+xml'

  when /json/
    send_file @json_file, :type => 'application/x-yaml' 

  when /yaml/
    file = "#{@@datadir}/#{params[:id]}.yaml"
    unless File.exists? file # lazy yaml generation
      dataset = OpenTox::Dataset.from_json File.read(@json_file)
      File.open(file,"w+") { |f| f.puts dataset.to_yaml }
    end
    send_file file, :type => 'application/x-yaml' 

  when /html/
    response['Content-Type'] = 'text/html'
    OpenTox.text_to_html JSON.pretty_generate(JSON.parse(File.read(@json_file))) 

  when "text/csv"
    response['Content-Type'] = 'text/csv'
    OpenTox::Dataset.from_json(File.read(@json_file)).to_csv

  when /ms-excel/
    file = "#{@@datadir}/#{params[:id]}.xls"
    OpenTox::Dataset.from_json(File.read(@json_file)).to_xls.write(file) unless File.exists? file # lazy xls generation
    send_file file, :type => 'application/ms-excel'

  when /sdfile/
    response['Content-Type'] = 'chemical/x-mdl-sdfile'
    OpenTox::Dataset.from_json(File.read(@json_file)).to_sdf

#  when /uri-list/
#    response['Content-Type'] = 'text/uri-list'
#    Yajl::Parser.parse(File.read(@json_file)).to_urilist

  else
    raise OpenTox::NotFoundError.new "Content-type #{@accept} not supported."
  end
end

# Get metadata of the dataset
# @return [application/rdf+xml] Metadata OWL-DL
get '/:id/metadata' do
  metadata = OpenTox::Dataset.from_json(File.read(@json_file)).metadata
  
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
  @json_file = "#{@@datadir}/#{@id}.json"
  feature_uri = url_for("/#{@id}/feature/#{URI.encode(feature)}",:full) # work around  racks internal uri decoding
  metadata = OpenTox::Dataset.from_json(File.read(@json_file)).features[feature_uri]
  
  case @accept
  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    response['Content-Type'] = 'application/rdf+xml'
    serializer = OpenTox::Serializer::Owl.new
    serializer.add_feature feature_uri, metadata
    serializer.to_rdfxml
  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    metadata.to_yaml
  when /json/
    response['Content-Type'] = 'application/json'
    Yajl::Encoder.encode(metadata)
  end

end

# Get a list of all features
# @param [Header] Accept one of `application/rdf+xml, application-x-yaml, text/uri-list` (default application/rdf+xml)
# @return [application/rdf+xml, application-x-yaml, text/uri-list] Feature list 
get '/:id/features' do

  features = OpenTox::Dataset.from_json(File.read(@json_file)).features

  case @accept
  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    response['Content-Type'] = 'application/rdf+xml'
    serializer = OpenTox::Serializer::Owl.new
    features.each { |feature,metadata| serializer.add_feature feature, metadata }
    serializer.to_rdfxml
  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    features.to_yaml
  when /json/
    response['Content-Type'] = 'application/json'
    Yajl::Encoder.encode(features)
  when "text/uri-list"
    response['Content-Type'] = 'text/uri-list'
    features.keys.join("\n") + "\n"
  end
end

# Get a list of all compounds
# @return [text/uri-list] Feature list 
get '/:id/compounds' do
  response['Content-Type'] = 'text/uri-list'
  OpenTox::Dataset.from_json(File.read(@json_file)).compounds.join("\n") + "\n"
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
  @json_file = "#{@@datadir}/#{@id}.json"
  if params.size == 0 and input_data.size==0
    File.open(@json_file,"w+"){|f| f.puts OpenTox::Dataset.new(@uri).to_json}
    OpenTox::Authorization.check_policy(@uri, @subjectid) if File.exists? @json_file
    @uri
  else
    task = OpenTox::Task.create("Converting and saving dataset ", @uri) do 
      load_dataset @id, params, request.content_type, input_data 
      OpenTox::Authorization.check_policy(@uri, @subjectid) if File.exists? @json_file
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
  response['Content-Type'] = 'text/uri-list'
  task = OpenTox::Task.create("Converting and saving dataset ", @uri) do 
    FileUtils.rm Dir["#{@@datadir}/#{@id}.*"]
    load_dataset @id, params, request.content_type, request.env["rack.input"].read 
    @uri
  end
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end


# Create PC descriptors
#
# @param [String] pc_type
# @return [text/uri-list] Task ID 
get '/:id/pcdesc' do
algorithm = OpenTox::Algorithm::Generic.new(url_for('/dataset/id/pcdesc',:full))
  algorithm.metadata = {
    DC.title => 'Physico-chemical (PC) descriptor calculation',
    DC.creator => "andreas@maunz.de, vorgrimmlerdavid@gmx.de",
    RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised],
    OT.parameters => [
      { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
      { DC.description => "PC type", OT.paramScope => "mandatory", DC.title => "pc_type" },
  ]
  }
  case request.env['HTTP_ACCEPT']
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html algorithm.to_yaml
  when /application\/x-yaml/
    content_type "application/x-yaml"
    algorithm.to_yaml
  else
    response['Content-Type'] = 'application/rdf+xml'  
    algorithm.to_rdfxml
  end
end



post '/:id/pcdesc' do
  response['Content-Type'] = 'text/uri-list'
  raise "No PC type given" unless params["pc_type"]

  task = OpenTox::Task.create("PC descriptor calculation for dataset ", @uri) do |task|
    types = params[:pc_type].split(",")
    if types.include?("joelib")
      Rjb.load(nil,["-Xmx64m"]) 
      s = Rjb::import('JoelibFc')
    end
    OpenTox::Algorithm.pc_descriptors( { :dataset_uri => @uri, :pc_type => params[:pc_type], :rjb => s, :task => task } )
  end
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end



# Deletes datasets that have been created by a crossvalidatoin that does not exist anymore
# (This can happen if a crossvalidation fails unexpectedly)
delete '/cleanup' do
  Dir["./#{@@datadir}/*json"].each do |file|
    dataset = OpenTox::Dataset.from_json File.read(file)
    if dataset.metadata[DC.creator] && dataset.metadata[DC.creator] =~ /crossvalidation\/[0-9]/
      begin
        cv = OpenTox::Crossvalidation.find(dataset.metadata[DC.creator],@subjectid)
        raise unless cv
      rescue
        LOGGER.debug "deleting #{dataset.uri}, crossvalidation missing: #{dataset.metadata[DC.creator]}"
        begin
          dataset.delete @subjectid
        rescue
        end
      end
    end 
  end
  "cleanup done"   
end

# Delete a dataset
# @return [text/plain] Status message
delete '/:id' do
  LOGGER.debug "deleting dataset with id #{@id}"
  begin
    FileUtils.rm Dir["#{@@datadir}/#{@id}.*"]
    if @subjectid and !File.exists? @json_file and @uri
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
  FileUtils.rm Dir["#{@@datadir}/*.rdfxml"]
  FileUtils.rm Dir["#{@@datadir}/*.xls"]
  FileUtils.rm Dir["#{@@datadir}/*.yaml"]
  FileUtils.rm Dir["#{@@datadir}/*.json"]
  response['Content-Type'] = 'text/plain'
  "All datasets deleted."
end
