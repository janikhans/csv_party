require 'csv_party'

class IntegerParserImporter < CSVParty
  column :integer, header: 'Integer', as: :integer
  column :whitespace, header: 'Whitespace', as: :integer
  column :decimal_as_integer, header: 'Decimal', as: :integer

  import do |row|
    $result = row
  end
end