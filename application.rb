module OpenTox
  class Application < Service

    @warnings = []

    helpers do
      def from_csv(csv)
        from_table CSV.parse(csv)
      end

=begin
      def parse_sdf(sdf)

        #obconversion = OpenBabel::OBConversion.new
        #obmol = OpenBabel::OBMol.new
        #obconversion.set_in_and_out_formats "sdf", "inchi"

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
            compound = OpenTox::Compound.from_sdf sdf
            #obconversion.read_string obmol, s
            table.last << obconversion.write_string(obmol).gsub(/\s/,'').chomp 
          rescue
            # TODO: Fix, will lead to follow up errors
            table.last << "Could not convert structure at record #{rec}) have been ignored! \n#{s}"
          end
          obmol.get_data.each { |d| table.last[table.first.index(d.get_attribute)] = d.get_value }
        end
        from_table table
      end
=end

      def from_table table

        @warnings = []
        ntriples = ["<#{@uri}> <#{RDF.type}> <#{RDF::OT.Dataset}>."]
        ntriples << ["<#{@uri}> <#{RDF.type}> <#{RDF::OT.OrderedDataset}>."]

        # features
        feature_names = table.shift.collect{|f| f.strip}
        @warnings << "Duplicated features in table header." unless feature_names.size == feature_names.uniq.size
        compound_format = feature_names.shift.strip
        bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: URI, SMILES, InChI." unless compound_format =~ /URI|URL|SMILES|InChI/i
        features = []
        ignored_feature_indices = []
        feature_names.each_with_index do |f,i|
          feature = OpenTox::Feature.new File.join($feature[:uri], SecureRandom.uuid)
          feature[RDF::DC.title] = f
          features << feature
          values = table.collect{|row| row[i+1].strip unless row[i+1].nil?}.uniq # skip compound column
          if values.size <= 3 # max classes
            feature.append RDF.type, RDF::OT.NominalFeature
            feature.append RDF.type, RDF::OT.StringFeature
            feature[RDF::OT.acceptValue] = values
          else
            types = values.collect{|v| feature_type(v)}
            if types.include?(RDF::OT.NominalFeature)
              @warnings << "Feature '#{f}' contains nominal and numeric values."
            else
              feature.append RDF.type, RDF::OT.NumericFeature
            end
          end
          feature.put
          ntriples << "<#{feature.uri}> <#{RDF.type}> <#{RDF::OT.Feature}>."
          ntriples << "<#{feature.uri}> <#{RDF::OLO.index}> #{i} ."
        end

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
          ntriples << "<#{compound_uri}> <#{RDF::OLO.index}> #{j} ."

          values.each_with_index do |v,i|
            @warnings << "Empty value for compound '#{compound}' (row #{j+2}) and feature '#{feature_names[i]}' (column #{i+2})." if v.blank?

            data_entry_node = "_:dataentry"+ j.to_s
            value_node = data_entry_node+ "_value"+ i.to_s
            ntriples << "<#{@uri}> <#{RDF::OT.dataEntry}> #{data_entry_node} ."
            ntriples << "#{data_entry_node} <#{RDF.type}> <#{RDF::OT.DataEntry}> ."
            ntriples << "#{data_entry_node} <#{RDF::OLO.index}> #{j} ."
            ntriples << "#{data_entry_node} <#{RDF::OT.compound}> <#{compound_uri}> ."
            ntriples << "#{data_entry_node} <#{RDF::OT.values}> #{value_node} ."
            ntriples << "#{value_node} <#{RDF::OT.feature}> <#{features[i].uri}> ."
            ntriples << "#{value_node} <#{RDF::OT.value}> \"#{v}\" ."

          end

        end

        ntriples << "<#{@uri}> <#{RDF::OT.Warnings}> \"#{@warnings.join('\n')}\" ."
        ntriples.join("\n")
      end

      def ordered?
        sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.OrderedDataset}>}"
        FourStore.query(sparql, "text/uri-list").split("\n").empty? ? false : true
      end

      def to_csv
        accept = "text/uri-list"
        csv_string = CSV.generate do |csv|
          if ordered?
            sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Feature}> . ?s <#{RDF::OLO.index}> ?i} ORDER BY ?i"
            features = FourStore.query(sparql, accept).split("\n").collect{|uri| OpenTox::Feature.new uri}
            csv << ["SMILES"] + features.collect{ |f| f.get; f[RDF::DC.title] }
            sparql = "SELECT DISTINCT ?i FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.DataEntry}> . ?s <#{RDF::OLO.index}> ?i} ORDER BY ?i"
            FourStore.query(sparql, accept).split("\n").each do |data_entry_idx|
              sparql = "SELECT DISTINCT ?compound FROM <#{@uri}> WHERE {
                ?data_entry <#{RDF::OLO.index}> #{data_entry_idx} ;
                  <#{RDF::OT.compound}> ?compound. }"
              compound = OpenTox::Compound.new FourStore.query(sparql, accept).strip
              sparql = "SELECT ?value FROM <#{@uri}> WHERE {
                ?data_entry <#{RDF::OLO.index}> #{data_entry_idx} ;
                  <#{RDF::OT.values}> ?v .
                ?v <#{RDF::OT.feature}> ?f;
                  <#{RDF::OT.value}> ?value .
                ?f <#{RDF::OLO.index}> ?i.

                  } ORDER BY ?i"
              csv << [compound.to_smiles] + FourStore.query(sparql,accept).split("\n")
            end
          else
            sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Feature}>}"
            features = FourStore.query(sparql, accept).split("\n").collect{|uri| OpenTox::Feature.new uri}
            csv << ["SMILES"] + features.collect{ |f| f.get; f[RDF::DC.title] }
            sparql = "SELECT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Compound}>. }"
            compounds = FourStore.query(sparql, accept).split("\n").collect{|uri| OpenTox::Compound.new uri}
            compounds.each do |compound|
              data_entries = []
              features.each do |feature|
                sparql = "SELECT ?value FROM <#{@uri}> WHERE {
                  ?data_entry <#{RDF::OT.compound}> <#{compound.uri}>;
                    <#{RDF::OT.values}> ?v .
                  ?v <#{RDF::OT.feature}> <#{feature.uri}>;
                    <#{RDF::OT.value}> ?value.
                    } ORDER BY ?data_entry"
                FourStore.query(sparql, accept).split("\n").each_with_index do |value,i|
                  data_entries[i] = [] unless data_entries[i]
                  data_entries[i] << value
                end
              end
              data_entries.each{|data_entry| csv << [compound.to_smiles] + data_entry}
            end
          end
        end
        csv_string
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

      def parse_put
        task = OpenTox::Task.create $task[:uri], nil, RDF::DC.description => "Dataset upload: #{@uri}" do
          case @content_type
          when "text/plain", "text/turtle", "application/rdf+xml" # no conversion needed
          when "text/csv"
            @body = from_csv @body
            @content_type = "text/plain"
          when "application/vnd.ms-excel"
            xls = params[:file][:tempfile].path + ".xls"
            File.rename params[:file][:tempfile].path, xls # roo needs these endings
            @body = from_csv Excel.new(xls).to_csv
            @content_type = "text/plain"
          when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            xlsx = params[:file][:tempfile].path + ".xlsx"
            File.rename params[:file][:tempfile].path, xlsx # roo needs these endings
            @body = from_csv Excelx.new(xlsx).to_csv
            @content_type = "text/plain"
          when "application/vnd.oasis.opendocument.spreadsheet"
            ods = params[:file][:tempfile].path + ".ods"
            File.rename params[:file][:tempfile].path, ods # roo needs these endings
            @body = from_csv Excelx.new(ods).to_csv
            @content_type = "text/plain"
    #      when "chemical/x-mdl-sdfile"
    #        @body = parse_sdf @body
    #        @content_type = "text/plain"
          else
            bad_request_error "#{@content_type} is not a supported content type."
          end
          FourStore.put @uri, @body, @content_type
          if params[:file]
            nt = "<#{@uri}> <#{RDF::DC.title}> \"#{params[:file][:filename]}\".\n<#{uri}> <#{RDF::OT.hasSource}> \"#{params[:file][:filename]}\"."
            FourStore.post(uri, nt, "text/plain")
          end
          @uri
        end
        response['Content-Type'] = "text/uri-list"
        task.uri
      end
    end

    before "/#{SERVICE}/:id/:property" do
      @uri = uri("/#{SERVICE}/#{params[:id]}")
    end

    # Create a new resource
    post "/dataset/?" do
      @uri = uri("/#{SERVICE}/#{SecureRandom.uuid}")
      parse_put
    end

    get "/dataset/:id/?" do
      case @accept
      when "application/rdf+xml", "text/turtle", "text/plain", /html/
        FourStore.get(@uri, @accept)
      else
        case @accept
        when "text/csv"
          to_csv
        #when "application/vnd.ms-excel"
        #when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        #when "application/vnd.oasis.opendocument.spreadsheet"
        #when "chemical/x-mdl-sdfile"
        else
          bad_request_error "'#{@accept}' is not a supported content type."
        end
      end
    end

    # Create or updata a resource
    put "/dataset/:id/?" do
      parse_put
    end

    # Get metadata of the dataset
    # @return [application/rdf+xml] Metadata OWL-DL
    get '/dataset/:id/metadata' do
      case @accept
      when "application/rdf+xml", "text/turtle", "text/plain"
        sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{@uri}> WHERE {<#{@uri}> ?p ?o. }"
        FourStore.query sparql, @accept
      else
        bad_request_error "'#{@accept}' is not a supported content type."
      end
    end

    # Get a list of all features
    # @param [Header] Accept one of `application/rdf+xml, text/turtle, text/plain, text/uri-list` (default application/rdf+xml)
    # @return [application/rdf+xml, text/turtle, text/plain, text/uri-list] Feature list 
    get '/dataset/:id/features' do
      case @accept
      when "application/rdf+xml", "text/turtle", "text/plain"
        sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Feature}>; ?p ?o. }"
      when "text/uri-list"
        sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Feature}>. }"
      else
        bad_request_error "'#{@accept}' is not a supported content type."
      end
      FourStore.query sparql, @accept
    end

    # Get a list of all compounds
    # @return [text/uri-list] Feature list 
    get '/dataset/:id/compounds' do
      accept = request.env['HTTP_ACCEPT']
      case accept
      when "application/rdf+xml", "text/turtle", "text/plain"
        sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Compound}>; ?p ?o. }"
      when "text/uri-list"
        sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Compound}>. }"
      else
        bad_request_error "'#{accept}' is not a supported content type."
      end
      FourStore.query sparql, accept
    end
  end
end

