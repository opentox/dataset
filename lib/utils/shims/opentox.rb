=begin
* Name: opentox.rb
* Description: Architecture shims
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

# This avoids having to prefix everything with "RDF::" (e.g. "RDF::DC").
# So that we can use our old code mostly as is.
include RDF

module OpenTox

    # Help function to provide the metadata= functionality.
    # Downward compatible to opentox-ruby.
    # @param [Hash] Key-Value pairs with the metadata
    # @return self
    def metadata=(hsh) 
      hsh.each {|k,v|
        self[k]=v
      }
    end


    ### Index Structures
    
    # Create parameter positions map
    # @return [Hash] A hash with keys parameter names and values parameter positions
    def build_parameter_positions
      unless @parameter_positions
        @parameters = parameters
        @parameter_positions = @parameters.each_index.inject({}) { |h,idx|
          h[@parameters[idx][DC.title.to_s]] = idx
          h
        }
      end
    end


    ### Associative Search Operations
    
    # Search a model for a given parameter
    # @param[String] The parameter title
    # @return[Object] The parameter value
    def find_parameter_value(title)
      build_parameter_positions
      res = @parameters[@parameter_positions[title]][OT.paramValue.to_s] if @parameter_positions[title]
      res
    end

end
