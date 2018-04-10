require 'test_helper'

class CsvDataTest < Minitest::Test
  class CsvImporter < CSVParty::Importer
    column :value

    rows do |row|
      self.result = row
    end
  end

  def test_csv_path
    importer = CsvImporter.new('test/fixtures/csv_data.csv')
    importer.import!
    assert_equal 'value', importer.result.value

    importer = CsvImporter.new
    importer.csv = 'test/fixtures/csv_data.csv'
    importer.import!
    assert_equal 'value', importer.result.value
  end

  def test_csv_file
    csv_file = File.open('test/fixtures/csv_data.csv')
    importer = CsvImporter.new(csv_file)
    importer.import!
    assert_equal 'value', importer.result.value

    csv_file = File.open('test/fixtures/csv_data.csv')
    importer = CsvImporter.new
    importer.csv = csv_file
    importer.import!
    assert_equal 'value', importer.result.value
  end

  def test_csv_string
    csv_string = <<-CSV
Value
value
    CSV

    importer = CsvImporter.new(csv_string)
    importer.import!
    assert_equal 'value', importer.result.value

    importer = CsvImporter.new
    importer.csv = csv_string
    importer.import!
    assert_equal 'value', importer.result.value
  end

  def test_raises_error_on_missing_csv
    importer = CsvImporter.new

    assert_raises CSVParty::MissingCSVError do
      importer.import!
    end
  end

  def test_raises_error_on_invalid_csv
    assert_raises CSVParty::InvalidCSVError do
      CsvImporter.new(1)
    end

    assert_raises CSVParty::InvalidCSVError do
      importer = CsvImporter.new
      importer.csv = 1
      importer.import!
    end
  end

  def test_raises_error_on_invalid_csv_file
    invalid_path = 'invalid/path/to/file'

    assert_raises CSVParty::NonexistentCSVFileError do
      CsvImporter.new(invalid_path)
    end

    assert_raises CSVParty::NonexistentCSVFileError do
      importer = CsvImporter.new
      importer.csv = invalid_path
    end
  end
end
