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
        extensions = { Roo::Excel => ".xls", Roo::Excelx => ".xlsx", Roo::Openoffice => ".ods" }
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

        data = {}
        data["warnings"] = []
        data["type"] = ["Dataset","OrderedDataset"]
        data["date"] = DateTime.now.to_s
        data["data_entries"] = []

        # features
        feature_names = table.shift.collect{|f| f.strip}
        data["warnings"] << "Duplicate features in table header." unless feature_names.size == feature_names.uniq.size
        compound_format = feature_names.shift.strip
        bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: URI, SMILES, InChI." unless compound_format =~ /URI|URL|SMILES|InChI/i
        data["features"] = []
        ignored_feature_indices = []
        feature_names.each_with_index do |f,i|
          values = table.collect{|row| val=row[i+1]; val.strip! unless val.nil?; val }.uniq.compact
          types = values.collect{|v| feature_type(v)}.uniq
          metadata = {"title" => f}
          if values.size == 0 # empty feature
          elsif values.size <= 5 # max classes
            metadata["type"] = [ "NominalFeature", "StringFeature", "Feature" ]
            metadata["acceptValue"] = values
          end
          if types.size == 1 and types[0] == "NumericFeature"
            metadata["type"] ||= [] 
            metadata["type"] << ["NumericFeature", "Feature"]
          else
            metadata["type"] = [ "NominalFeature", "StringFeature", "Feature" ] # only nominal type for mixed cases
            metadata["acceptValue"] = values
          end
          feature = OpenTox::Feature.find_or_create metadata
          data["features"] << feature.uri unless feature.nil?
        end

        # compounds and values
        data["compounds"] = []
        r = -1
        table.each_with_index do |values,j|
          compound = values.shift
          compound_uri = nil
          begin
            case compound_format
            when /URI|URL/i
              compound_uri = compound
            when /SMILES/i
              c = OpenTox::Compound.from_smiles(compound)
              if c.inchi.empty?
                data["warnings"] << "Cannot parse #{compound_format} compound '#{compound}' at position #{j+2}, all entries are ignored."
                next
              else
                compound_uri = c.uri
              end
            when /InChI/i
              c = OpenTox::Compound.from_inchi(compound)
              if c.inchi.empty?
                data["warnings"] << "Cannot parse #{compound_format} compound '#{compound}' at position #{j+2}, all entries are ignored."
                next
              else
                compound_uri = c.uri
              end
            else
              raise "wrong compound format" #should be checked above
            end
          rescue
            data["warnings"] << "Cannot parse #{compound_format} compound '#{compound}' at position #{j+2}, all entries are ignored." # be careful with double quotes in literals! \C in smiles is an illegal Turtle string
            next
          end
          
          r += 1
          data["compounds"] << compound_uri
          unless values.size == data["features"].size
            data["warnings"] << "Number of values at position #{j+2} (#{values.size}) is different than header size (#{features.size}), all entries are ignored."
            next
          end

          # TODO ordering/index
          #data_entry_node = "<#{File.join @uri,"dataentry",j.to_s}>" # too slow or not accepted by 4store

          data["data_entries"] << values
          values.each_with_index do |v,i|
            if v.blank?
              data["warnings"] << "Empty value for compound '#{compound}' (row #{r+2}) and feature '#{feature_names[i]}' (column #{i+2})."
              next
            end
          end
        end
        data["compounds"].duplicates.each do |uri|
          positions = []
          data["compounds"].each_with_index{|c,i| positions << i+1 if !c.blank? and c == uri}
          data["warnings"] << "Duplicate compound #{uri} at rows #{positions.join(', ')}. Entries are accepted, assuming that measurements come from independent experiments." 
        end
        data
      end

      def to_csv
        csv_string = CSV.generate do |csv|
          to_table.each { |row| csv << row }
        end
        csv_string.gsub(/\"\"/,"") # AM: no quotes for missing values
        #to_table
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
        table
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
        task = OpenTox::Task.run "Dataset upload", @uri do
          case @content_type
          when "application/json" # no conversion needed
          #when "text/plain", "text/turtle", "application/rdf+xml" # no conversion needed
          when "text/csv", "text/comma-separated-values"
            @body = from_csv @body
    #      when "chemical/x-mdl-sdfile"
    #        @body = parse_sdf @body
    #        @content_type = "text/plain"
          else
            bad_request_error "#{@content_type} is not a supported content type."
          end
          if params["file"]
            @body[:title] = params["file"][:filename]
            @body[:hasSource] = params["file"][:filename]
          end
          
          @body["uri"] = @uri
          @body["uuid"] = @uri.split(/\//).last
          $mongo[SERVICE].insert_one(@body).inspect
          @uri
        end
        response['Content-Type'] = "text/uri-list"
        halt 202, task.uri
      end
    end

  end
end

