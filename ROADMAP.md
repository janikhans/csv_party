Roadmap
-

- [1.1 Early Return While Parsing](#11-early-return-while-parsing)
- [1.2 Rows to Hash](#12-rows-to-hash)
- [1.3 Generate Unimported Rows CSV](#13-generate-unimported-rows-csv)
- [1.4 Batch API](#14-batch-api)
- [1.5 Runtime Configuration](#15-runtime-configuration)
- [1.6 CSV Parse Error Handling](#16-csv-parse-error-handling)
- [Someday Features](#someday-features)
    - [Parse Row Access](#parse-row-access)
    - [Deferred Parsing](#deferred-parsing)
    - [Columns Macro](#columns-macro)
    - [Column Numbers](#column-numbers)
    - [Multi-column Parsing](#multi-column-parsing)
    - [Parse Dependencies](#parse-dependencies)
    - [Rails Generator](#rails-generator0

#### 1.1 Early Return While Parsing

Currently, CSVParty is pretty well thought out about what should happen when
either 1) one of the built in flow control methods (`next_row`, `skip_row`,
`abort_row`, and `abort_import`) is used, or 2) an error is raised while
the row importer block is being executed. However, all of these things can also
happen when the columns for a row are being parsed. When/if it does, most of the
flow control and error handling kind of assumes that the row has been fully
parsed. So some design work should go into deciding what should happen in these
cases. And then tests should be written for all of the various scenarios.

#### 1.2 Rows to Hash

One of the primary use cases for importing CSV files is to insert their contents
into a database. Apparently this is common enough that the
[csv-importer](https://github.com/pcreux/csv-importer) gem, which almost
completely automates this process without much room for customization, is very
popular. So, in the case where there is a pretty simple correspondence between
the contents of a CSV file and ActiveRecord models, it should be dead simple to
get the job done.

What I have in mind is something like:

    class MyImporter < CSVParty::Importer
      column :product_id
      column :quantity
      column :price

      rows do |row|
        LineItem.create(row.attributes)
      end
    end

Where `row.attributes` returns a hash with all of the column names as keys and
all of the parsed values as values. So, with an importer like the one above,
`row.attributes` would return a hash like so:

    { product_id: 42, quantity: 3, price: 9.99 }

#### 1.3 Generate Unimported Rows CSV

Most user inputs to an application are relatively constrained. CSV files, on the
other hand, are not. Users can, and will, put all kinds of erroneous data into
their CSV files. So, it is useful to be able to provide a user with a list of
the rows in their file that could not be imported, so that they can re-import
these rows after they have resolved whatever issues existed. And CSV is a
natural format for this, since the user can open the file in Excel and make
edits.

A motivated user of CSVParty can already achieve this by accessing the
`skipped_rows`, `aborted_rows`, and `error_rows` arrays and constructing one or
more CSV files from these, but it would be nice to provide a default
implementation that is only a method call away. What I have in mind is for the
CSV file that is created to have the exact same column structure as the original
file, but with three additional columns:

  - The original row number
  - The status (skipped, aborted, errored)
  - A message explaining the reason for the status

Conveniently, all of these pieces of data are available for skipped, aborted,
and errored rows. Then, the file would be generated with a method, like so:

    # all three combined
    importer.unimported_rows_as_csv
    # or separate
    importer.skipped_rows_as_csv
    importer.aborted_rows_as_csv
    importer.error_rows_as_csv

#### 1.4 Batch API

It can be way more performant to batch imports so that expensive operations,
like persisting data, are only done every so often. This would add an API to
accumulate data, execute some logic every X number of rows, reset the
accumulators, then repeat. Here's a rough sketch of what that API might look
like:

    rows do |row|
      customers[row.customer_id] = { name: row.customer_name, phone: row.phone }
      orders[row.order_id] = { customer_id: row.customer_id, invoice_number: row.invoice_number }
    end

    batch 50, customers: {}, orders: {} do
      # insert customers into database
      # insert orders into database
    end

The first argument is how often the batch logic should be executed. In this
case, every 50 rows. Then there is a hash of accumulators, where the keys are
the names of the accumulators and the values are the initial values. Declaring
the accumulators accomplished two things:

1. It provides accessor methods so that the accumulators can be accessed from
   within the row import block.
2. It automatically resets the accumulators to their initial values each time
   the batch block is executed.

So, it is essentially functionally identical to doing the following:

    class MyImporter < CSVParty::Importer
      attr_accessor :customers, :orders

      def customers
        @customers ||= {}
      end

      def orders
        @orders ||= {}
      end

      rows do |row|
        # add customer to customers accumulator
        # add order to orders accumulator
      end

      batch 50 do
        # insert customers into database
        # insert orders into database
        customers = {}
        orders = {}
      end
    end

_Note:_ The following is a rough sketch of an API that would handle a use case
that has come up. However, some research should be done first to figure out if
the use case it addresses is common.

One use case that has been mentioned is when rows are grouped by their
relationship to a parent record and those rows need to be acted on as a group.
So, imagine a CSV file like so:

    Customer,Address,Product,Quantity,Price
    Joe Smith,123 Main St.,Birkenstocks,1,74.99
    Joe Smith,123 Main St.,Air Jordans,1,129.99
    Joe Smith,123 Main St.,Tevas,3,59.99
    Jane Doe,713 Broadway,Converse All-Star,1,39.99
    Jane Doe,713 Broadway,Toms,1,59.99

It might be useful to be able to specify the batch interval in terms of one of
the columns in the CSV file, rather than as a number of rows. So, you would be
able to do:

    class MyImporter < CSVParty::Importer
      column :customer
      column :address
      column :product
      column :quantity, as: :integer
      column :price, as: :decimal

      rows do |row|
        line_items << { product: row.product, quantity: row.quantity, price: row.price }
      end

      batch :customer, line_items: [] do |current_row|
        Customer.create(name: current_row.customer, address: current_row.address)
        line_items.each do |li|
          LineItem.create(li)
        end
      end
    end

In this case, the batch logic gets executed everytime there is a change in the
`:customer` column from one row to the next, rather than every X number of rows.
The accumulator works the same way: accessors are made available for adding
records to the accumulator and then the accumulator is automatically reset to
its initial value each time the batch logic is executed.

#### 1.5 Runtime Configuration

Sometimes it useful to be able to configure an importer at runtime, rather than
at code writing time. An obvious example of when this would be useful is in the
case of user defined column header names. So, imagine a UI in which the user
uploads their CSV file, then specifies which column is, for example, the product
column, which is the quantity column, and which is the price column. In a case
like this, there is no way to specify the column definitions ahead of time; we
have to wait for the header names from the user.

Here is a sketch of what the API for runtime configuration would look like:

    class MyImporter < CSVParty::Importer
      rows do |row|
        # persist data
      end
    end

    # then:

    my_importer = MyImporter.new
    my_importer.configure do
      column :product, header: user_product_header
      column :quantity, header: user_quantity_header, as: :integer
      column :price, header: user_price_header, as: :decimal
    end

An open question is whether all DSL methods should be configurable at runtime.

#### 1.6 CSV Parse Error Handling

Sometimes it is useful to be able to completely ignore parsing and encoding
errors raised by the `CSV` class. To be clear, doing so is dangerous, since the
parsing logic in the `CSV` class is not designed to continue operating after it
encounters an error and raises. But sometimes you don't want to let a single
improperly encoded character prevent you from importing an entire CSV file. So,
this feature would be an optional way to either ignore those errors or respond
to them, and then continue importing. The API would probably be similar to the
error handling API for non-parse errors. So:

    parse_errors :ignore # silently continue importing the next row

    parse_errors do |line_number|
      # handle parse error
    end

    my_import.parse_error_rows # returns array of parse error rows

## Someday Features

#### Parse Row Access

This feature would allow access to the `CSV::Row` object when parsing a column.
It could work something like this:

    column product do |value, row|
      Product.find_by(name: row['Product'])
    end

In theory, the CSVParty API would cover all use cases where somebody would need
to access the raw row data, but perhaps not. Sometimes it's nice to be able to
cut through the stuff in your way and just get at the raw internals.

Additionally, perhaps deferred parsing would allow access to parsed row values,
which would possibly enable some of the features below, Multi Column Parsing and
Parse Dependencies, without requiring additional code. That might look like:

    column product do |value, row|
      Product.find_by(name: row.unparsed.row)
    end

#### Deferred Parsing

Currently, CSVParty parses all columns before the row import logic is executed.
There are situations where parsing columns is expensive and you may want to
defer parsing columns until and unless you actually need them for that a given
row. For example, say you have an import where you are either:

1. Updating a value on existing records, or
2. Setting a value on and creating new records

And when you create new records, you have to also set a bunch of other values
and some of those values require database queries.

In a situation like this, you would want to defer all of the database queries
that need to run when creating a new record so that they aren't done in cases
where you are updating an existing record.

#### Columns Macro

This feature would allow you to declare multiple columns in a single line. So,
rather than:

    column :product
    column :price
    column :color

You could do:

    columns :product, :price, :color

This is probably most useful when there are a bunch of columns that should all
be parsed as text. Though it might make sense to allow specifying parsers and
other options:

    columns product: { as: :raw }, price: { as: :decimal }

It should probably also be possible to combine `columns` and `column` macros:

    columns :product, :price, :color
    column :size

#### Column Numbers

CSVParty is entirely oriented around a CSV file having a header. This is not
always the case, though. This would add the ability to specify columns using a
column number, rather than a header. A rough sketch of the API might look like:

    class MyImporter < CSVParty::Importer
      column :product, number: 7
      column :quantity, number: 8, as: :integer
      column :price, number: 9, as: :decimal
    end

#### Multi-column Parsing

The whole idea behind custom parsers is that it makes for much cleaner code to
get all the logic related to parsing a raw value into a useful intermediate
object in one place, away from the larger logic of what needs to happen to each
row. Sometimes, though, you need access to multiple column values to create a
useful parsed value. Here is what an API for that might look like:

    column :total, header: ['Price', 'Quantity'] do |price, quantity|
      BigDecimal(price) * BigDecimal(quantity)
    end

#### Parse Dependencies

Sometimes, while parsing a column, it would be useful to have access to the
parsed value from another column. This would make that possible. Here is what
that might look like:

    class MyImporter < CSVParty::Importer
      column :customer do |customer_id|
        Customer.find(customer_id)
      end

      column :order, depends_on: :customer do |order_id, customer|
        customer.orders.find(order_id)
      end
    end

#### Rails Generator

This feature would add a generator for Rails which creates an importer file. So
doing:

    rails generate importer Product

Would generate the following file at `app/importers/product_importer.rb`:

    class ProductImporter
      include CSVParty

      import do |row|
        # import logic goes here
      end
    end

