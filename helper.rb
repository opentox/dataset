# Author: Christoph Helma, Andreas Maunz

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
          values = table.collect{|row| val=row[i+1]; val.strip! unless val.nil?; val }.uniq.compact
          types = values.collect{|v| feature_type(v)}.uniq
          metadata = {RDF::DC.title => f}
          if values.size == 0 # empty feature
          elsif values.size <= 5 # max classes
            metadata[RDF.type] = [ RDF::OT.NominalFeature, RDF::OT.StringFeature ]
            metadata[RDF::OT.acceptValue] = values
          end
          if types.size == 1 and types[0] == RDF::OT.NumericFeature
            metadata[RDF.type] = [] unless metadata[RDF.type]
            metadata[RDF.type] << RDF::OT.NumericFeature 
          else
            metadata[RDF.type] = [ RDF::OT.NominalFeature, RDF::OT.StringFeature ] # only nominal type for mixed cases
            metadata[RDF::OT.acceptValue] = values
          end
          feature = OpenTox::Feature.find_or_create metadata, @subjectid # AM: find or generate
          features << feature unless feature.nil?
          ntriples << "<#{feature.uri}> <#{RDF.type}> <#{RDF::OT.Feature}>."
          ntriples << "<#{feature.uri}> <#{RDF::OLO.index}> #{i} ."
        end

        # compounds and values
        compound_uris = []
        table.each_with_index do |values,j|
          compound = values.shift
          puts "'#{compound}'"
          begin
            case compound_format
            when /URI|URL/i
              compound_uri = compound
            when /SMILES/i
              compound_uri = OpenTox::Compound.from_smiles(compound).uri
            when /InChI/i
              compound_uri = OpenTox::Compound.from_inchi(compound).uri
            when ""
              @warnings << "Cannot parse compound '#{compound}' at position #{j+2}, all entries are ignored." # be careful with double quotes in literals! \C in smiles is an illegal Turtle string
              next
            end
          rescue
            @warnings << "Cannot parse compound '#{compound}' at position #{j+2}, all entries are ignored." # be careful with double quotes in literals! \C in smiles is an illegal Turtle string
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
        compound_uris.duplicates.each do |uri|
          positions = []
          compound_uris.each_with_index{|c,i| positions << i+1 if c == uri}
          @warnings << "Duplicate compound #{uri} at rows #{positions.join(', ')}. Entries are accepted, assuming that measurements come from independent experiments." 
        end

        ntriples << "<#{@uri}> <#{RDF::OT.Warnings}> \"#{@warnings.join('\n')}\" ."
        ntriples.join("\n")
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
        csv_string.gsub(/\"\"/,"") # AM: no quotes for missing values
        #to_table
      end

      def compound_uris
      end

      def features
      end

      def data_entries
      end

      def to_table
        # TODO: fix and speed up 
        sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {
          ?s <#{RDF.type}> <#{RDF::OT.Feature}> ;
             <#{RDF::OLO.index}> ?fidx
          } ORDER BY ?fidx"
        features = FourStore.query(sparql, "text/uri-list").split("\n").collect { |uri| OpenTox::Feature.new uri }
        sparql = "SELECT DISTINCT ?compound FROM <#{@uri}> WHERE {
          ?compound <#{RDF.type}> <#{RDF::OT.Compound}> ;
                    <#{RDF::OLO.index}> ?cidx;
          } ORDER BY ?cidx"
        inchis = FourStore.query(sparql, "text/uri-list").split("\n").collect { |uri| "InChI#{uri.split("InChI").last}" }

        table  = [["InChI"] + features.collect{|f| f.title}]
        inchis.each{|inchi| table << [inchi]}
        sparql = "SELECT ?cidx ?fidx ?value FROM <#{@uri}> WHERE {
          ?data_entry <#{RDF::OLO.index}> ?cidx ;
                      <#{RDF::OT.values}> ?v .
          ?v          <#{RDF::OT.feature}> ?f;
                      <#{RDF::OT.value}> ?value .
          ?f          <#{RDF::OLO.index}> ?fidx.
          } ORDER BY ?fidx ?cidx" 
        FourStore.query(sparql,"text/uri-list").split("\n").each do |row|
          r,c,v = row.split("\t")
          table[r.to_i+1][c.to_i+1] = v.to_s
        end
        table#.inspect
=begin
        table = []
        dataset = OpenTox::Dataset.new @uri
        table << ["SMILES"] + dataset.features.collect{|f| f.title}
        dataset.data_entries.each_with_index do |data_entry,i|
          table << [dataset.compounds[i]] + data_entry
        end
        table
=end
=begin
        accept = "text/uri-list"
        table  = []
        if ordered?
          features = OpenTox::Dataset.find_features_sparql(@uri)
          sparql_constraints = {:type => RDF.type, :title => RDF::DC.title}
          feature_props = OpenTox::Dataset.find_props_sparql(features.collect { |f| f.uri }, sparql_constraints)
          quoted_features = []; feature_names = []
          features.each { |feature|
              quoted_features << feature_props[feature.uri][:type].include?(RDF::OT.NominalFeature)
              feature_names << "\"#{feature_props[feature.uri][:title][0].strip}\""
          }
          compounds = OpenTox::Dataset.find_compounds_sparql(@uri)
          values = OpenTox::Dataset.find_data_entries_sparql(@uri)
          values += Array.new(compounds.size*features.size-values.size, "")
          clim=(compounds.size-1)
          cidx = fidx = 0
          num=(!quoted_features[fidx])
          table = (Array.new((features.size)*(compounds.size))).each_slice(features.size).to_a
          values.each { |val|
            unless val.blank?
              table[cidx][fidx] = (num ? val : "\"#{val}\"")
            end
            if (cidx < clim)
              cidx+=1
            else
              cidx=0
              fidx+=1
              num=(!quoted_features[fidx])
            end
          }
          table.each_with_index { |row,idx| row.unshift("\"#{compounds[idx].inchi}\"") }
          table.unshift([ "\"InChI\"" ] + feature_names)
        else
          sparql = "SELECT DISTINCT ?s FROM <#{@uri}> WHERE {?s <#{RDF.type}> <#{RDF::OT.Feature}>}"
          features = FourStore.query(sparql, accept).split("\n").collect{|uri| OpenTox::Feature.new uri}.each { |f| f.get }
          quoted_features = features.each_with_index.collect { |f,idx|
            if (f[RDF.type].include?(RDF::OT.NominalFeature) or 
                f[RDF.type].include?(RDF::OT.StringFeature) and
               !f[RDF.type].include?(RDF::OT.NumericFeature))
              idx+1 
            end
          }.compact
          table << ["InChI"] + features.collect{ |f| "\"" + f[RDF::DC.title] + "\"" }
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
              FourStore.query(sparql, accept).split("\n").each do |value|
                data_entries << value
              end
            end
            row = ["\"#{compound.inchi}\""] + data_entries
            row = row.each_with_index.collect { |value,idx| (quoted_features.include?(idx) ? "\"#{value}\"" : value) }
            table << row
          end
        end
        table
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
        task = OpenTox::Task.run "Dataset upload", @uri, @subjectid do
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
          if params["file"]
            nt = "<#{@uri}> <#{RDF::DC.title}> \"#{params["file"][:filename]}\".\n<#{uri}> <#{RDF::OT.hasSource}> \"#{params["file"][:filename]}\"."
            FourStore.put(@uri, nt, "text/plain")
          end
          nt ? FourStore.post(@uri, @body, @content_type) : FourStore.put(@uri, @body, @content_type) 
          @uri
        end
        response['Content-Type'] = "text/uri-list"
        halt 202, task.uri
      end
    end

  end
end

