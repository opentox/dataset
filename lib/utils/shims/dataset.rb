=begin
* Name: dataset.rb
* Description: Dataset shims
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox

  # Shims for the Dataset Class
  class Dataset

    attr_accessor :feature_positions, :compound_positions

    # Load a dataset from URI
    # @param [String] Dataset URI
    # @return [OpenTox::Dataset] Dataset object
    def self.find(uri, subjectid=nil)
      return nil unless uri
      ds = OpenTox::Dataset.new uri, subjectid
      ds.get
      ds
    end



    ### Index Structures

    # Create value map
    # @param [OpenTox::Feature] A feature
    # @return [Hash] A hash with keys 1...feature.training_classes.size and values training classes
    def value_map(feature)
      training_classes = feature.accept_values
      training_classes.each_index.inject({}) { |h,idx| h[idx+1]=training_classes[idx]; h } 
    end

    # Create feature positions map
    # @return [Hash] A hash with keys feature uris and values feature positions
    def build_feature_positions
      unless @feature_positions
        @feature_positions = @features.each_index.inject({}) { |h,idx| 
          internal_server_error "Duplicate Feature '#{@features[idx].uri}' in dataset '#{@uri}'" if h[@features[idx].uri]
          h[@features[idx].uri] = idx 
          h
        }
      end
    end

    # Create compounds positions map
    # @return [Hash] A hash with keys compound uris and values compound position arrays
    def build_compound_positions
      unless @compound_positions
        @compound_positions = @compounds.each_index.inject({}) { |h,idx| 
          inchi=OpenTox::Compound.new(@compounds[idx].uri).inchi
          h[inchi] = [] unless h[inchi]
          h[inchi] << idx if inchi =~ /InChI/
          h
        }
      end
    end


    ### Associative Search Operations

    # Search a dataset for a feature given its URI
    # @param [String] Feature URI
    # @return [OpenTox::Feature] Feature object, or nil if not present
    def find_feature(uri)
      build_feature_positions
      res = @features[@feature_positions[uri]] if @feature_positions[uri]
      res
    end

    # Search a dataset for a compound given its URI
    # @param [String] Compound URI
    # @return [OpenTox::Compound] Array of compound objects, or nil if not present
    def find_compound(uri)
      build_compound_positions
      inchi = OpenTox::Compound.new(uri).inchi
      res = @compounds[@compound_positions[inchi]] if inchi =~ /InChI/ and @compound_positions[inchi]
      res
    end

    # Search a dataset for a data entry given compound URI and feature URI
    # @param [String] Compound URI
    # @param [String] Feature URI
    # @return [Object] Data entry, or nil if not present
    def find_data_entry(compound_uri, feature_uri)
      build_compound_positions
      build_feature_positions
      inchi = OpenTox::Compound.new(compound_uri).inchi
      if @compound_positions[inchi] && @feature_positions[feature_uri]
        res = []
        @compound_positions[inchi].each { |idx|
          res << data_entries[idx][@feature_positions[feature_uri]]
        }
      end
      res
    end

  end


end
