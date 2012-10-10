# dataset.rb
# OpenTox dataset
# Author: Andreas Maunz

module OpenTox

  class Application < Service


    # Get a list of descriptor calculation 
    # @return [text/uri-list] URIs
    get '/dataset/*/pc' do
      dataset=params["captures"][0]
      algorithms = YAML::load_file File.join(ENV['HOME'], ".opentox", "config", "pc_descriptors.yaml")
      list = (algorithms.keys.sort << "AllDescriptors").collect { |name| url_for("/dataset/#{dataset}/pc/#{name}",:full) }.join("\n") + "\n"
      format_output(list)
    end
    
    # Get representation of descriptor calculation
    # @return [String] Representation
    get '/dataset/*/pc/*' do
      dataset = params[:captures][0]
      params[:descriptor] = params[:captures][1]
      descriptors = YAML::load_file File.join(ENV['HOME'], ".opentox", "config", "pc_descriptors.yaml")
      alg_params = [ 
        { DC.description => "Dataset URI", 
          OT.paramScope => "mandatory", 
          DC.title => "dataset_uri" } 
      ]
      if params[:descriptor] != "AllDescriptors"
        descriptors = descriptors[params[:descriptor]]
      else
        alg_params << { 
          DC.description => "Physico-chemical type, one or more of '#{descriptors.collect { |id, info| info[:pc_type] }.uniq.sort.join(",")}'", 
          OT.paramScope => "optional", DC.title => "pc_type" 
        }
        alg_params << { 
          DC.description => "Software Library, one or more of '#{descriptors.collect { |id, info| info[:lib] }.uniq.sort.join(",")}'", 
          OT.paramScope => "optional", DC.title => "lib" 
        }
        descriptors = {:id => "AllDescriptors", :name => "All PC descriptors" } # Comes from pc_descriptors.yaml for single descriptors
      end
    
      if descriptors 
        # Contents
        algorithm = OpenTox::Algorithm.new(url_for("/dataset/#{dataset}/pc/#{params[:descriptor]}",:full))
        mmdata = {
          DC.title => params[:descriptor],
          DC.creator => "andreas@maunz.de",
          DC.description => descriptors[:name],
          RDF.type => [OTA.DescriptorCalculation],
        }
        mmdata[DC.description] << (", pc_type: " + descriptors[:pc_type]) unless descriptors[:id] == "AllDescriptors"
        mmdata[DC.description] << (", lib: " + descriptors[:lib])         unless descriptors[:id] == "AllDescriptors"
        algorithm.metadata=mmdata
        algorithm.parameters = alg_params
        format_output(algorithm)
      else
        resource_not_found_error "Unknown descriptor #{params[:descriptor]}."
      end
    end


    # Calculate PC descriptors
    # Single descriptors or sets of descriptors can be selected
    # Sets are selected via lib and/or pc_type, and take precedence, when also a descriptor is submitted
    # If none of descriptor, lib, and pc_type is submitted, all descriptors are calculated
    # Set composition is induced by intersecting lib and pc_type sets, if appropriate
    # @param [optional, HEADER] accept Accept one of 'application/rdf+xml', 'text/csv', defaults to 'application/rdf+xml'
    # @param [optional, String] descriptor A single descriptor to calculate values for.
    # @param [optional, String] lib One or more descriptor libraries out of [cdk,joelib,openbabel], for whose descriptors to calculate values.
    # @param [optional, String] pc_type One or more descriptor types out of [constitutional,topological,geometrical,electronic,cpsa,hybrid], for whose descriptors to calculate values
    # @return [application/rdf+xml,text/csv] Compound descriptors and values
    post '/dataset/*/pc' do
      dataset=params["captures"][0]
      params.delete('splat')
      params.delete('captures')
      params_array = params.collect{ |k,v| [k.to_sym, v]}
      params = Hash[params_array]
      params[:dataset] = dataset
      descriptor = params[:descriptor].nil? ? "" : params[:descriptor]
      lib = params[:lib].nil? ? "" : params[:lib]
      pc_type = params[:pc_type].nil? ? "" : params[:pc_type]

      task = OpenTox::Task.create(
                                 $task[:uri],
                                 @subjectid,
                                 { RDF::DC.description => "Calculating PC descriptors",
                                   RDF::DC.creator => url_for("/dataset/#{dataset}/pc",:full)
                                 }
                                ) do |task|

       begin
         result_ds = OpenTox::Dataset.new(nil,@subjectid)
         ds=OpenTox::Dataset.find("#{$dataset[:uri]}/#{dataset}",@subjectid)
         $logger.debug "AM: #{ds.compounds.size} compounds"
         ds.compounds.each { |cmpd|
           ds_string = OpenTox::RestClientWrapper.post("#{$compound[:uri]}/#{cmpd.inchi}/pc", params, {:accept => "application/rdf+xml"})
           single_cmpd_ds = OpenTox::Dataset.new(nil,@subjectid)
           single_cmpd_ds.parse_rdfxml(ds_string)
           single_cmpd_ds.get(true)
           unless result_ds.features.size>0 # features present already?
             result_ds.features = single_cmpd_ds.features # AM: features
             result_ds.parameters = ["pc_type", "lib", "descriptor"].collect{ |key| # AM: parameters
               val = single_cmpd_ds.find_parameter_value(key)
               { DC.title => key, OT.paramValue => (val.nil? ? "" : val) }
             }
             result_ds[RDF.type] = single_cmpd_ds[RDF.type] # AM: metadata
             result_ds[DC.title] = single_cmpd_ds[DC.title]
             result_ds[DC.creator] = url_for("/dataset/#{dataset}/pc",:full)
             result_ds[OT.hasSource] = url_for("/dataset/#{dataset}/pc",:full)
           end
           result_ds << [ cmpd ] + single_cmpd_ds.data_entries[0]
         }
         result_ds.put @subjectid
         $logger.debug result_ds.uri
         result_ds.uri

       rescue => e
         $logger.debug "#{e.class}: #{e.message}"
         $logger.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
       end

      end
      response['Content-Type'] = 'text/uri-list'
      service_unavailable_error "Service unavailable" if task.cancelled?
      halt 202,task.uri.to_s+"\n"
    end

  end

end

