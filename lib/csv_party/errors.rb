module CSVParty
  class Error < StandardError
  end

  class UnknownParserError < Error
    def initialize(column, parser, named_parsers)
      parser  = parser.to_s.gsub('parse_', '')
      parsers = named_parsers.map { |p| p.to_s.gsub('parse_', '') }

      super <<-MESSAGE
You're trying to use the :#{parser} parser for the :#{column} column, but it
doesn't exist. Available parsers are: :#{parsers.join(', :')}.
      MESSAGE
    end
  end

  class MissingCSVError < Error
    def initialize(importer)
      super <<-MESSAGE
You must specify a file path, IO object, or string to import:

    # File path, IO object, or string
    csv = 'path/to/csv'
    csv = File.open('path/to/csv')
    csv = 'Header1,Header2\\nvalue1,value2\\n'

Then, you assign that to your importer one of two ways:

    importer = #{importer.class.name}.new(csv)
    # or
    importer = #{importer.class.name}.new
    importer.csv = csv
      MESSAGE
    end
  end

  class NonexistentCSVFileError < Error
    def initialize(file_path)
      super <<-MESSAGE
The CSV file you are trying to import was not found:

    #{file_path}

NOTE: If you are trying to import a single line CSV string, please ensure that
your CSV string has a header row and at least one row of values. Single line
strings are assumed to be a path to a CSV file.
      MESSAGE
    end
  end

  class UnrecognizedOptionsError < Error
    def initialize(unrecognized_options, valid_data_options, valid_csv_options, dependencies)
      @unrecognized_options = unrecognized_options
      @valid_data_options = valid_data_options
      @valid_csv_options = valid_csv_options
      @dependencies = dependencies

      super csv_and_data_options_message + dependency_options_message
    end

    def csv_and_data_options_message
      <<-MESSAGE
The following options are not recognized: :#{@unrecognized_options.join(', :')}.
You can specify your CSV data via the :path, :file, or :content options, as well
as any options that the CSV library understands:

    :#{@valid_csv_options.join("\n    :")}
      MESSAGE
    end

    def dependency_options_message
      return '' unless @dependencies.any?

      <<-MESSAGE

Or assignments for dependencies:

    :#{@dependencies.join("\n    :")}
      MESSAGE
    end
  end

  class DuplicateColumnError < Error
    def initialize(name)
      super <<-MESSAGE
A column named :#{name} has already been defined, please choose a different name.
      MESSAGE
    end
  end

  class ReservedColumnNameError < Error
    def initialize(reserved_column_names)
      super <<-MESSAGE
The following column names are reserved for interal use, please use a different
column name: :#{reserved_column_names.join(', :')}.
      MESSAGE
    end
  end

  class MissingColumnError < Error
    def initialize(headers, missing_columns)
      columns = missing_columns.join("', '")
      super <<-MESSAGE
The CSV is missing column(s) with header(s) '#{columns}'. File has these
headers: #{headers.join(', ')}.
      MESSAGE
    end
  end

  class UndefinedRowProcessorError < Error
    def initialize
      super <<-MESSAGE
Your importer has to define a row processor which specifies what should be done
with each row. It should look something like this:

    rows do |row|
      row.column  # access parsed column values
      row.unparsed.column  # access unparsed column values
    end
      MESSAGE
    end
  end

  class MissingDependencyError < Error
    def initialize(importer, dependency)
      super <<-MESSAGE
This importer depends on #{dependency}, but you didn't assign it.
You can do that when instantiating your importer:

    #{importer.class.name}.new('path/to/csv', #{dependency}: #{dependency})

Or any time before you import:

    importer = #{importer.class.name}.new('path/to/csv')
    importer.#{dependency} = #{dependency}
    importer.import!
      MESSAGE
    end
  end

  class UnimportedRowsError < Error
    def initialize
      super <<-MESSAGE
The rows in your CSV file have not been imported.

You should include a call to import_rows! at the point in your import block
where you want them to be imported. It should should look something like this:

    import do
      # do stuff before importing rows
      import_rows!
      # do stuff after importing rows
    end
      MESSAGE
    end
  end
end
