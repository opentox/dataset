require "openbabel"
module OpenTox

  # Perform OpenBabel conversions locally in order to prevent net overhead
	class Compound 

    attr_writer :smiles, :inchi

    # Create a compound from smiles string
    # @example
    #   compound = OpenTox::Compound.from_smiles("c1ccccc1")
    # @param [String] smiles Smiles string
    # @return [OpenTox::Compound] Compound
    def self.from_smiles smiles, subjectid=nil
			inchi = obconversion(smiles,'smi','inchi')
      compound = Compound.new(File.join service_uri, inchi)
      compound.inchi = inchi
      compound.smiles = smiles
      compound
    end

    # Create a compound from inchi string
    # @param [String] smiles InChI string
    # @return [OpenTox::Compound] Compound
    def self.from_inchi inchi, subjectid=nil
      compound = Compound.new(File.join service_uri, inchi)
      compound.inchi = inchi
      compound
    end

    # Create a compound from sdf string
    # @param [String] smiles SDF string
    # @return [OpenTox::Compound] Compound
    def self.from_sdf sdf, subjectid=nil
			inchi = obconversion(sdf,'sdf','inchi')
      compound = Compound.new(File.join service_uri, inchi)
      compound.inchi = inchi
      compound
    end

    private
    
    # Convert identifier from OpenBabel input_format to OpenBabel output_format
    def self.obconversion(identifier,input_format,output_format)
      obconversion = OpenBabel::OBConversion.new
      obmol = OpenBabel::OBMol.new
      obconversion.set_in_and_out_formats input_format, output_format
      obconversion.read_string obmol, identifier
      case output_format
      when /smi|can|inchi/
        obconversion.write_string(obmol).gsub(/\s/,'').chomp
      else
        obconversion.write_string(obmol)
      end
    end
  end

end
