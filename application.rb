# dataset.rb
# Loads libraries and webapps
# Author: Christoph Helma, Andreas Maunz

require 'roo'
require 'base64'

# Library code
$logger.debug "Dataset booting: #{$dataset.collect{|k,v| "#{k}: '#{v}'"} }"
Dir['./lib/utils/shims/*.rb'].each { |f| require f } # Shims for legacy code
Dir['./lib/utils/*.rb'].each { |f| require f } # Utils for Libs
Dir['./lib/compound/*.rb'].each { |f| require f } # Libs
Dir['./lib/*.rb'].each { |f| require f } # Libs
Dir['./webapp/*.rb'].each { |f| require f } # Webapps

#require 'profiler'

# Entry point
module OpenTox
  class Application < Service

    @warnings = []

    helpers do

      def from_csv(csv)
        table = CSV.parse(csv)
        # CSVs with unexpected encodings may have blanks instead of nil
        table.collect! { |row| 
          row.collect! { |val| 
            (val.class == String and val.strip == "") ? nil : val 
          } 
        }
        from_table table
      end

      def from_spreadsheet spreadsheet
        extensions = { Excel => ".xls", Excelx => ".xlsx", Openoffice => ".ods" }
        input = params[:file][:tempfile].path + ".xls"
        csv_file = params[:file][:tempfile].path + ".csv"
        File.rename params[:file][:tempfile].path, input # roo needs "correct" extensions
        spreadsheet.new(input).to_csv csv_file # roo cannot write to strings
        @body = from_csv File.read(csv_file)
        @content_type = "text/plain"
      end

=begin
      def from_sdf(sdf)

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

=begin
        dataset = OpenTox::Dataset.new @uri
        puts dataset.uri
        feature_names = table.shift.collect{|f| f.strip}
        puts feature_names.inspect
        dataset.append RDF::OT.Warnings, "Duplicate features in table header." unless feature_names.size == feature_names.uniq.size
        compound_format = feature_names.shift.strip
        bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: URI, SMILES, InChI." unless compound_format =~ /URI|URL|SMILES|InChI/i
        features = []
        feature_names.each_with_index do |f,i|
          feature = OpenTox::Feature.new File.join($feature[:uri], SecureRandom.uuid)
          feature[RDF::DC.title] = f
          features << feature
          values = table.collect{|row| row[i+1].strip unless row[i+1].nil?}.uniq.compact # skip compound column
          if values.size <= 3 # max classes
            feature.append RDF.type, RDF::OT.NominalFeature
            feature.append RDF.type, RDF::OT.StringFeature
            feature[RDF::OT.acceptValue] = values
          else
            types = values.collect{|v| feature_type(v)}
            if types.include?(RDF::OT.NominalFeature)
              dataset.append RDF::OT.Warnings, "Feature #{f} contains nominal and numeric values."
            else
              feature.append RDF.type, RDF::OT.NumericFeature
            end
          end
          feature.put
        end
        dataset.features = features
        compounds = []
        table.each_with_index do |values,j|
          c = values.shift
          puts c
          puts compound_format
          values.collect!{|v| v.nil? ? nil : v.strip }
          #begin
            case compound_format
            when /URI|URL/i
              compound = OpenTox::Compound.new c
            when /SMILES/i
              compound = OpenTox::Compound.from_smiles($compound[:uri], c)
            when /InChI/i
              compound = OpenTox::Compound.from_inchi($compound[:uri], URI.decode_www_form_component(c))
            end
          #rescue
            #dataset.append RDF::OT.Warnings, "Cannot parse compound \"#{c}\" at position #{j+2}, all entries are ignored."
            #next
          #end
          unless compound_uri.match(/InChI=/)
            dataset.append RDF::OT.Warnings, "Cannot parse compound \"#{c}\" at position #{j+2}, all entries are ignored."
            next
          end
          compounds << compound
          unless values.size == features.size
            dataset.append RDF::OT.Warnings, "Number of values at position #{j+2} (#{values.size}) is different than header size (#{features.size}), all entries are ignored."
            next
          end

          dataset << values

        end
        dataset.compounds = compounds
        compounds.duplicates.each do |compound|
          positions = []
          compounds.each_with_index{|c,i| positions << i+1 if c.uri == compound.uri}
          dataset.append RDF::OT.Warnings, "Duplicate compound #{compound.uri} at rows #{positions.join(', ')}. Entries are accepted, assuming that measurements come from independent experiments." 
        end
        puts dataset.to_ntriples
        dataset.to_ntriples
=end

        @warnings = []
        ntriples = ["<#{@uri}> <#{RDF.type}> <#{RDF::OT.Dataset}>."]
        ntriples << ["<#{@uri}> <#{RDF.type}> <#{RDF::OT.OrderedDataset}>."]

        # features
        feature_names = table.shift.collect{|f| f.strip}
        @warnings << "Duplicate features in table header." unless feature_names.size == feature_names.uniq.size
        compound_format = feature_names.shift.strip
        bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: URI, SMILES, InChI." unless compound_format =~ /URI|URL|SMILES|InChI/i
        features = []
        ignored_feature_indices = []
        feature_names.each_with_index do |f,i|
          feature = OpenTox::Feature.new File.join($feature[:uri], SecureRandom.uuid)
          feature[RDF::DC.title] = f
          features << feature
          values = table.collect{|row| row[i+1].strip! unless row[i+1].nil?}.uniq.compact
          types = values.collect{|v| feature_type(v)}.uniq
          if values.size == 0
          elsif values.size <= 5 # max classes
            feature.append RDF.type, RDF::OT.NominalFeature
            feature.append RDF.type, RDF::OT.StringFeature
            feature[RDF::OT.acceptValue] = values
          end
          if types.size == 1 and types[0] == RDF::OT.NumericFeature
            feature.append RDF.type, RDF::OT.NumericFeature 
          else
            feature.append RDF.type, RDF::OT.NominalFeature # only nominal type for mixed cases
            feature.append RDF.type, RDF::OT.StringFeature
            feature[RDF::OT.acceptValue] = values
          end
          feature.put
          ntriples << "<#{feature.uri}> <#{RDF.type}> <#{RDF::OT.Feature}>."
          ntriples << "<#{feature.uri}> <#{RDF::OLO.index}> #{i} ."
        end

        # compounds and values
        compound_uris = []
        table.each_with_index do |values,j|
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
          rescue
            @warnings << "Cannot parse compound \"#{compound}\" at position #{j+2}, all entries are ignored."
            next
          end
          unless compound_uri.match(/InChI=/)
            @warnings << "Cannot parse compound \"#{compound}\" at position #{j+2}, all entries are ignored."
            next
          end
          compound_uris << compound_uri
          unless values.size == features.size
            @warnings << "Number of values at position #{j+2} (#{values.size}) is different than header size (#{features.size}), all entries are ignored."
            next
          end
          ntriples << "<#{compound_uri}> <#{RDF.type}> <#{RDF::OT.Compound}>."
          ntriples << "<#{compound_uri}> <#{RDF::OLO.index}> #{j} ."

          values.each_with_index do |v,i|
            #@warnings << "Empty value for compound #{compound} (row #{j+2}) and feature \"#{feature_names[i]}\" (column #{i+2})." if v.blank?
            #@warnings << "Empty value in row #{j+2}, column #{i+2} (feature \"#{feature_names[i]}\")." if v.blank?

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
        compound_uris.duplicates.each do |uri|
          positions = []
          compound_uris.each_with_index{|c,i| positions << i+1 if c == uri}
          @warnings << "Duplicate compound #{uri} at rows #{positions.join(', ')}. Entries are accepted, assuming that measurements come from independent experiments." 
        end

        ntriples << "<#{@uri}> <#{RDF::OT.Warnings}> \"#{@warnings.join('\n')}\" ."
        ntriples.join("\n")
=begin
=end
      end

=begin
      def to_xlsx

        # both simple_xlsx and axlsx create empty documents with OLE2 errors
        xlsx = @uri.split("/").last+".xlsx"
        p = Axlsx::Package.new
        wb = p.workbook
        wb.add_worksheet(:name => "test") do |sheet|
          to_table.each { |row| sheet.add_row row; puts row }
        end
        p.serialize("test.xlsx")

        p.to_stream
#```
        #Tempfile.open(@uri.split("/").last+".xlsx") do |xlsx|
          SimpleXlsx::Serializer.new(xlsx) do |doc|
            doc.add_sheet("People") do |sheet|
              to_table.each { |row| sheet.add_row row }
            end
          end
          send_file xlsx
        #end
      end
=end

      def to_csv
        csv_string = CSV.generate do |csv|
          to_table.each { |row| csv << row }
        end
      end

      def to_table
=begin
        table = []
        dataset = OpenTox::Dataset.new @uri
        dataset.get
        table << ["SMILES"] + dataset.features.collect{|f| f.get; f.title}
        dataset.data_entries.each_with_index do |data_entry,i|
          table << [dataset.compounds[i]] + data_entry
        end
        table
=end
        accept = "text/uri-list"
        table  = []
        if ordered?
          sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Feature}> . ?s <#{RDF::OLO.index}> ?i} ORDER BY ?i"
          features = FourStore.query(sparql, accept).split("\n").collect{|uri| OpenTox::Feature.new uri}
          table << ["SMILES"] + features.collect{ |f| f.get; f[RDF::DC.title] }
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
            values = FourStore.query(sparql,accept).split("\n")
            # Fill up trailing empty cells
            table << [compound.smiles] + values.fill("",values.size,features.size-values.size)
          end
        else
          sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Feature}>}"
          features = FourStore.query(sparql, accept).split("\n").collect{|uri| OpenTox::Feature.new uri}
          table << ["SMILES"] + features.collect{ |f| f.get; f[RDF::DC.title] }
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
                data_entries[i] = Array.new(features.size) unless data_entries[i]
                data_entries[i] << value
              end
            end
            data_entries.each{|data_entry| table << [compound.smiles] + data_entry}
          end
        end
        table
=begin
=end
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

      def ordered?
        sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.OrderedDataset}>}"
        FourStore.query(sparql, "text/uri-list").split("\n").empty? ? false : true
      end

      def parse_put
        task = OpenTox::Task.create $task[:uri], nil, RDF::DC.description => "Dataset upload: #{@uri}" do
          #Profiler__::start_profile
          case @content_type
          when "text/plain", "text/turtle", "application/rdf+xml" # no conversion needed
          when "text/csv"
            @body = from_csv @body
            @content_type = "text/plain"
          when "application/vnd.ms-excel"
            from_spreadsheet Excel
          when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            from_spreadsheet Excelx
          when "application/vnd.oasis.opendocument.spreadsheet"
            from_spreadsheet Openoffice
    #      when "chemical/x-mdl-sdfile"
    #        @body = parse_sdf @body
    #        @content_type = "text/plain"
          else
            bad_request_error "#{@content_type} is not a supported content type."
          end
          FourStore.put @uri, @body, @content_type
          if params[:file]
            nt = "<#{@uri}> <#{RDF::DC.title}> \"#{params[:file][:filename]}\".\n<#{uri}> <#{RDF::OT.hasSource}> \"#{params[:file][:filename]}\"."
            FourStore.post(@uri, nt, "text/plain")
          end
          #Profiler__::stop_profile
          #Profiler__::print_profile($stdout)
          @uri
        end
        response['Content-Type'] = "text/uri-list"
        halt 202, task.uri
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
      #Profiler__::start_profile
      @accept = "text/html" if @accept == '*/*'
      case @accept
      when "application/rdf+xml", "text/turtle", "text/plain", /html/
        r = FourStore.get(@uri, @accept)
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
      #Profiler__::stop_profile
      #Profiler__::print_profile($stdout)
      r
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
      case @accept
      when "application/rdf+xml", "text/turtle", "text/plain"
        sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Compound}>; ?p ?o. }"
      when "text/uri-list"
        sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Compound}>. }"
      else
        bad_request_error "'#{@accept}' is not a supported content type."
      end
      FourStore.query sparql, @accept
    end
  end
end

