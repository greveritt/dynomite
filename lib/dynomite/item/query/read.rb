module Dynomite::Item::Query
  module Read
    extend ActiveSupport::Concern

    def find(id)
      self.class.find(id)
    end

    class_methods do
      # Adds very little wrapper logic to scan.
      #
      # * Automatically add table_name to options for convenience.
      # * Decorates return value.  Returns Array of [MyModel.new] instead of the
      #   dynamodb client response.
      #
      # Other than that, usage is same was using the dynamodb client scan method
      # directly.  Example:
      #
      #   MyModel.scan(
      #     expression_attribute_names: {"#updated_at"=>"updated_at"},
      #     expression_attribute_values: {
      #       ":start_time" => "2010-01-01T00:00:00",
      #       ":end_time" => "2020-01-01T00:00:00"
      #     },
      #     filter_expression: "#updated_at between :start_time and :end_time",
      #   )
      #
      # AWS Docs examples: http://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GettingStarted.Ruby.04.html
      def scan(params={})
        Dynomite.logger.info("It's recommended to not use scan for production. It can be slow and expensive. You can a LSI or GSI and query the index instead.")
        Dynomite.logger.info("Scanning table: #{table_name}")
        params = { table_name: table_name }.merge(params)
        resp = db.scan(params)
        Dynomite.logger.info("REQUEST: #{params}")
        resp.items.map {|i| self.new(i) }
      end

      # Adds very little wrapper logic to query.
      #
      # * Automatically add table_name to options for convenience.
      # * Decorates return value.  Returns Array of [MyModel.new] instead of the
      #   dynamodb client response.
      #
      # Other than that, usage is same was using the dynamodb client query method
      # directly.  Example:
      #
      #   MyModel.query(
      #     index_name: 'category-index',
      #     expression_attribute_names: { "#category_name" => "category" },
      #     expression_attribute_values: { ":category_value" => "Entertainment" },
      #     key_condition_expression: "#category_name = :category_value",
      #   )
      #
      # AWS Docs examples: http://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GettingStarted.Ruby.04.html
      def query(params={})
        params = { table_name: table_name }.merge(params)
        resp = db.query(params)
        resp.items.map { |i| self.new(i) }
      end

      def where(args)
        Builder.new(self).where(args)
      end

      %w[all first last].each do |meth|
        define_method(meth) do
          where({}).send(meth)
        end
      end

      def find_by(attrs)
        where(attrs).first
      end

      def find(id)
        params =
          case id
          when String, Symbol
            { partition_key => id }
          when Hash
            id
          end

        puts "find params:"
        pp params
        resp = db.get_item(
          table_name: table_name,
          key: params
        )
        puts "resp: #{resp}"
        attrs = resp.item # unwraps the item's attrs
        if attrs # is nil when no item found
          item = self.new(attrs)
          item.new_record = false
          item
        end
      end

      def count
        table.item_count # can be stale
      end

      def table
        Aws::DynamoDB::Table.new(name: table_name, client: db)
      end
    end
  end
end