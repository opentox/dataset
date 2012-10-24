=begin
* Name: feature.rb
* Description: Feature shims
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox

  # Shims for the feature class
  class Feature

    # Load a feature from URI
    # @param [String] Feature URI
    # @return [OpenTox::Feature] Feature object with the full data
    def self.find(uri, subjectid=nil)
      return nil unless uri
      f = OpenTox::Feature.new uri, subjectid
      f.get
      f
    end

    # Load or create a feature given its title and metadata
    # Create it if: a) not present, or b) present, but differs in metadata
    # Newly created features are stored at the backend
    # @param[String] title Feature title
    # @param[Hash] metadata Feature metadata
    # @return [OpenTox::Feature] Feature object with the full data, or nil
    def self.find_by_title(title, metadata)
      metadata[RDF.type] = [] unless metadata[RDF.type]
      metadata[RDF.type] << RDF::OT.Feature unless metadata[RDF.type].include?(RDF::OT.Feature)
      metadata[RDF::DC.title] = title unless (metadata[RDF::DC.title])
      feature = feature_new = OpenTox::Feature.new File.join($feature[:uri], SecureRandom.uuid), @subjectid
      feature_new.metadata = metadata
      sparql = "SELECT DISTINCT ?feature WHERE { ?feature <#{RDF.type}> <#{RDF::OT['feature'.capitalize]}>. ?feature <#{RDF::DC.title}> '#{title.to_s}' }"
      feature_uris = OpenTox::Backend::FourStore.query(sparql,"text/uri-list").split("\n")
      features_equal = false # relevant also when no features found
      feature_uris.each_with_index { |feature_uri,idx|
        feature_existing = OpenTox::Feature.find(feature_uri, @subjectid)
        if (feature_new.metadata.size+1 == feature_existing.metadata.size) # +1 due to title
          features_equal = metadata.keys.collect { |predicate|
            unless ( predicate == RDF::DC.title )
              if feature_new[predicate].class == feature_existing[predicate].class
                case feature_new[predicate].class.to_s
                  when "Array" then (feature_new[predicate].sort == feature_existing[predicate].sort)
                  else (feature_new[predicate] == feature_existing[predicate])
                end
              end
            else
              true
            end
          }.uniq == [true]
        end
        (feature=feature_existing and break) if features_equal
      }
      unless features_equal
        feature_new.put 
      end
      feature
    end

    # Find out feature type
    # Classification takes precedence
    # @return [String] Feature type
    def feature_type
      bad_request_error "rdf type of feature '#{@uri}' not set" unless self[RDF.type]
      if self[RDF.type].include?(OT.NominalFeature)
        "classification"
      elsif [RDF.type].to_a.flatten.include?(OT.NumericFeature)
        "regression"
      else
        "unknown"
      end
    end

    # Get accept values
    # @param[String] Feature URI
    # @return[Array] Accept values
    def accept_values
      accept_values = self[OT.acceptValue]
      accept_values.sort if accept_values
      accept_values
    end

  end

end
