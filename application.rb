# dataset.rb
# Loads libraries and webapps
# Author: Christoph Helma, Andreas Maunz

require 'roo'
require 'opentox-server'
require_relative 'helper.rb'
require_relative 'compound.rb'
# TODO: remove and find a better way to test task errors
require_relative 'test.rb'

# Library code
$logger.debug "Dataset booting: #{$dataset.collect{|k,v| "#{k}: '#{v}'"} }"

# Entry point
module OpenTox
  class Application < Service

    before "/#{SERVICE}/:id/:property" do
      @uri = uri("/#{SERVICE}/#{params[:id]}")
    end

    # Create a new resource
    post "/dataset/?" do
      @uri = uri("/#{SERVICE}/#{SecureRandom.uuid}")
      parse_put
    end

=begin
    get "/dataset/:id/?" do
      case @accept
      when "application/rdf+xml", "text/turtle", "text/plain", /html/
        r = FourStore.get(@uri.split('?').first, @accept)
      else
        case @accept
        when "text/csv"
          r = to_csv
        #when "application/vnd.ms-excel"
          #to_spreadsheet Excel
        #when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          #to_xlsx
        #when "application/vnd.oasis.opendocument.spreadsheet"
          #to_spreadsheet Openoffice
        #when "chemical/x-mdl-sdfile"
        else
          bad_request_error "'#{@accept}' is not a supported content type."
        end
      end
      r
    end
=end

    # Create or update a resource
    put "/dataset/:id/?" do
      parse_put
    end

    # Get metadata of the dataset
    # @return [application/rdf+xml] Metadata OWL-DL
    get '/dataset/:id/metadata' do
      render $mongo[SERVICE].find(:uri => @uri).first
      #render $mongo[SERVICE].find(:uri => @uri).projection(:data_entries => 0).first
      #case @accept
      #when "application/rdf+xml", "text/turtle", "text/plain"
      #else
      #  bad_request_error "'#{@accept}' is not a supported content type."
      #end
    end

    # Get a list of all features
    # @param [Header] Accept one of `application/rdf+xml, text/turtle, text/plain, text/uri-list` (default application/rdf+xml)
    # @return [application/rdf+xml, text/turtle, text/plain, text/uri-list] Feature data
    get '/dataset/:id/features' do
      render $mongo[SERVICE].find(:uri => @uri).distinct(:feature)
    end

    # Get a list of all compounds
    # @param [Header] Accept one of `application/rdf+xml, text/turtle, text/plain, text/uri-list` (default application/rdf+xml)
    # @return [application/rdf+xml, text/turtle, text/plain, text/uri-list] Compound data
    get '/dataset/:id/compounds' do
      case @accept
      when "application/json"
      #when "application/rdf+xml", "text/turtle", "text/plain"
        #sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Compound}>; ?p ?o. }"
      when "text/uri-list"
        #sparql = "SELECT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Compound}>. ?s <#{RDF::OLO.index}> ?idx } ORDER BY ?idx"
      else
        bad_request_error "'#{@accept}' is not a supported content type."
      end
      render $mongo[SERVICE].find(:uri => @uri).distinct(:compounds)
    end

  end
end

