#require "./parser.rb"
module OpenTox
  class Application < Service

    @warnings = []

    helpers do
      def parse_csv(csv)
        parse_table CSV.parse(csv)
      end

      def parse_sdf(sdf)

        obconversion = OpenBabel::OBConversion.new
        obmol = OpenBabel::OBMol.new
        obconversion.set_in_and_out_formats "sdf", "inchi"

        table = []

        properties = []
        sdf.each_line { |l| properties << l.to_s if l.match(/</) }
        properties.sort!
        properties.uniq!
        properties.collect!{ |p| p.gsub(/<|>/,'').strip.chomp }
        properties.insert 0, "InChI"
        table[0] = properties

        rec = 0
        sdf.split(/\$\$\$\$\r*\n/).each do |s|
          rec += 1
          table << []
          begin
            # TODO: use compound service
            obconversion.read_string obmol, s
            table.last << obconversion.write_string(obmol).gsub(/\s/,'').chomp 
          rescue
            # TODO: Fix, will lead to follow up errors
            table.last << "Could not convert structure at record #{rec}) have been ignored! \n#{s}"
          end
          obmol.get_data.each { |d| table.last[table.first.index(d.get_attribute)] = d.get_value }
        end
        parse_table table
      end

      def parse_table table

        @warnings = []
        dataset_uri =  File.join(uri("/dataset"), SecureRandom.uuid)
        #ntriples = []
        ntriples = ["<#{dataset_uri}> <#{RDF.type}> <#{RDF::OT.Dataset}>."]

        # features
        feature_names = table.shift.collect{|f| f.strip}
        @warnings << "Duplicated features in table header." unless feature_names.size == feature_names.uniq.size
        compound_format = feature_names.shift.strip
        bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: URI, SMILES, InChI." unless compound_format =~ /URI|URL|SMILES|InChI/i
        features = []
        ignored_feature_indices = []
        feature_names.each_with_index do |f,i|
          # TODO search for existing features
          feature = OpenTox::Feature.new File.join($feature[:uri], SecureRandom.uuid)
          feature[RDF.type] = RDF::OT.Feature
          feature[RDF::DC.title] = f
          features << feature
          values = table.collect{|row| row[i+1].strip unless row[i+1].nil?}.uniq # skip compound column
          if values.size <= 3 # max classes
            feature[RDF.type] = RDF::OT.NominalFeature
            feature[RDF.type] = RDF::OT.StringFeature
            feature[RDF::OT.acceptValue] = values
          else
            types = values.collect{|v| feature_type(v)}
            if types.include?(RDF::OT.NominalFeature)
              @warnings << "Feature '#{f}' contains nominal and numeric values."
              #ignored_feature_indices << i
              #next
            else
              feature[RDF.type] = RDF::OT.NumericFeature
            end
          end
          feature.save
          case feature[RDF.type].class.to_s
          when "Array"
            feature[RDF.type].each{ |t| ntriples << "<#{feature.uri}> <#{RDF.type}> <#{t}>." }
          when "String"
            ntriples << "<#{feature.uri}> <#{RDF.type}> <#{feature[RDF.type]}>."
          end
        end

        # remove invalid features from table
#        puts ignored_feature_indices.inspect
#        ignored_feature_indices.each do |i|
#          features.delete_at(i)
#          table.each{|row| row.delete_at(i)}
#        end

        # compounds and values
        compound_uris = []
        data_entry_idx = 0
        table.each_with_index do |values,j|
          values.collect!{|v| v.strip unless v.nil?}
          compound = values.shift
          begin
            case compound_format
            when /URI|URL/i
              compound_uri = compound
            when /SMILES/i
              compound_uri = OpenTox::Compound.from_smiles($compound[:uri], compound).uri
            when /InChI/i
              compound_uri = OpenTox::Compound.from_inchi($compound[:uri], URI.decode_www_form_component(compound)).uri
            end
            @warnings << "Duplicated compound #{compound} at position #{j+2}, entries are accepted, assuming that measurements come from independent experiments." if compound_uris.include? compound_uri
          rescue
            @warnings << "Cannot parse compound #{compound} at position #{j+2}, all entries are ignored."
            next
          end
          unless values.size == features.size
            @warnings << "Number of values at position #{j+2} (#{values.size}) is different than header size (#{features.size}), all entries are ignored."
            next
          end
          ntriples << "<#{compound_uri}> <#{RDF.type}> <#{RDF::OT.Compound}>."

          values.each_with_index do |v,i|
            @warnings << "Empty value for compound '#{compound}' (row #{j+2}) and feature '#{feature_names[i]}' (column #{i+2})." if v.blank?

            # TODO multiple values, use data_entry/value uris for sorted datasets
            # data_entry_uri = File.join dataset_uri, "dataentry", data_entry_idx
            ntriples << "<#{dataset_uri}> <#{RDF::OT.dataEntry}> _:dataentry#{data_entry_idx} ."
            ntriples << "_:dataentry#{data_entry_idx} <#{RDF.type}> <#{RDF::OT.DataEntry}> ."
            ntriples << "_:dataentry#{data_entry_idx} <#{RDF::OT.compound}> <#{compound_uri}> ."
            ntriples << "_:dataentry#{data_entry_idx} <#{RDF::OT.values}> _:values#{data_entry_idx} ."
            ntriples << "_:values#{data_entry_idx} <#{RDF::OT.feature}> <#{features[i].uri}> ."
            ntriples << "_:values#{data_entry_idx} <#{RDF::OT.value}> \"#{v}\" ."

            data_entry_idx += 1

          end

        end

        ntriples << "<#{dataset_uri}> <#{RDF::OT.Warnings}> \"#{@warnings.join('\n')}\" ."
        ntriples.join("\n")
      end

      def feature_type(value)
        if value.blank?
          nil
        elsif value.numeric?
          RDF::OT.NumericFeature
        else
          RDF::OT.NominalFeature
        end
      end

    end

    # Create a new resource
    post "/dataset/?" do
      #begin
        case @content_type
        when "text/plain", "text/turtle", "application/rdf+xml" # no conversion needed
        when "text/csv"
          @body = parse_csv @body
          @content_type = "text/plain"
        when "application/vnd.ms-excel"
          xls = params[:file][:tempfile].path + ".xls"
          File.rename params[:file][:tempfile].path, xls # roo needs these endings
          @body = parse_csv Excel.new(xls).to_csv
          @content_type = "text/plain"
        when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          xlsx = params[:file][:tempfile].path + ".xlsx"
          File.rename params[:file][:tempfile].path, xlsx # roo needs these endings
          @body = parse_csv Excelx.new(xlsx).to_csv
          @content_type = "text/plain"
        when "application/vnd.oasis.opendocument.spreadsheet"
          ods = params[:file][:tempfile].path + ".ods"
          File.rename params[:file][:tempfile].path, ods # roo needs these endings
          @body = parse_csv Excelx.new(ods).to_csv
          @content_type = "text/plain"
        when "chemical/x-mdl-sdfile"
          @body = parse_sdf @body
          @content_type = "text/plain"
        else
          bad_request_error "#{@content_type} is not a supported content type."
        end
        uri = uri("/#{SERVICE}/#{SecureRandom.uuid}")
        FourStore.put(uri, @body, @content_type)
        if params[:file]
          nt = "<#{uri}> <#{RDF::DC.title}> \"#{params[:file][:filename]}\".\n<#{uri}> <#{RDF::OT.hasSource}> \"#{params[:file][:filename]}\"."
          FourStore.post(uri, nt, "text/plain")
        end
      #rescue
        #bad_request_error $!.message
      #end

        #dataset.add_metadata({
        #DC.title => File.basename(params[:file][:filename],".csv"),
        #OT.hasSource => File.basename(params[:file][:filename])
      #})
      response['Content-Type'] = "text/uri-list"
      uri
    end

    # Create or updata a resource
    put "/dataset/:id/?" do
      FourStore.put uri("/#{SERVICE}/#{params[:id]}"), @body, @content_type
    end
    # Get metadata of the dataset
    # @return [application/rdf+xml] Metadata OWL-DL
    get '/dataset/:id/metadata' do
    end

    # Get a list of all features
    # @param [Header] Accept one of `application/rdf+xml, text/turtle, text/plain, text/uri-list` (default application/rdf+xml)
    # @return [application/rdf+xml, text/turtle, text/plain, text/uri-list] Feature list 
    get '/dataset/:id/features' do
      accept = request.env['HTTP_ACCEPT']
      uri = uri "/dataset/#{params[:id]}"
      case accept
      when "application/rdf+xml", "text/turtle", "text/plain"
        sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Feature}>; ?p ?o. }"
      when "text/uri-list"
        sparql = "SELECT DISTINCT ?s FROM <#{uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Feature}>. }"
      else
        bad_request_error "'#{accept}' is not a supported content type."
      end
      FourStore.query sparql, accept
    end

    # Get a list of all compounds
    # @return [text/uri-list] Feature list 
    get '/dataset/:id/compounds' do
      accept = request.env['HTTP_ACCEPT']
      uri = uri "/dataset/#{params[:id]}"
      case accept
      when "application/rdf+xml", "text/turtle", "text/plain"
        sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Compound}>; ?p ?o. }"
      when "text/uri-list"
        sparql = "SELECT DISTINCT ?s FROM <#{uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Compound}>. }"
      else
        bad_request_error "'#{accept}' is not a supported content type."
      end
      FourStore.query sparql, accept
    end
  end
end

=begin
require 'rubygems'
gem "opentox-ruby", "~> 3"
require 'opentox-ruby'
require 'profiler'
require 'rjb'

set :lock, true

@@datadir = "data"

@@idfile_path = @@datadir+"/id" 
unless File.exist?(@@idfile_path)
  id = Dir["./#{@@datadir}/*json"].collect{|f| File.basename(f.sub(/.json/,'')).to_i}.sort.last
  id = 0 if id.nil?
  open(@@idfile_path,"w") do |f|
    f.puts(id)
  end
end

helpers do
  def next_id
    open(@@idfile_path, "r+") do |f|
      f.flock(File::LOCK_EX)
      @id = f.gets.to_i + 1
      f.rewind
      f.print @id
    end
    return @id
  end

  def uri(id)
    url_for "/#{id}", :full
  end

  # subjectid ist stored as memeber variable, not in params
  def load_dataset(id, params,content_type,input_data)

    @uri = uri id
    raise "store subject-id in dataset-object, not in params" if params.has_key?(:subjectid) and @subjectid==nil

    content_type = "application/rdf+xml" if content_type.nil?
    dataset = OpenTox::Dataset.new(@uri, @subjectid) 

    case content_type

    when /yaml/
      dataset.load_yaml(input_data)

    when /json/
      dataset.load_json(input_data)

    when "text/csv"
      dataset.load_csv(input_data, @subjectid)

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
    send_file @json_file, :type => 'application/json' 

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
=end
