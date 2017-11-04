require "active_support/core_ext/hash"
require "aws-sdk-dynamodb"
require "digest"
require "yaml"

# The modeling is ActiveRecord-ish but not exactly because DynamoDB is a
# different type of database.
#
# Examples:
#
#   post = Post.new
#   post = post.replace(title: "test title")
#
# post.attrs[:id] now contain a generaetd unique partition_key id.
# Usually the partition_key is 'id'. You can set your own unique id also:
#
#   post = Post.new(id: "myid", title: "my title")
#   post.replace
#
# Note that the replace method replaces the entire item, so you
# need to merge the attributes if you want to keep the other attributes.
#
#   post = Post.find("myid")
#   post.attrs = post.attrs.deep_merge("desc": "my desc") # keeps title field
#   post.replace
#
# The convenience `attrs` method performs a deep_merge:
#
#   post = Post.find("myid")
#   post.attrs("desc": "my desc") # <= does a deep_merge
#   post.replace
#
# Note, a race condition edge case can exist when several concurrent replace
# calls are happening.  This is why the interface is called replace to
# emphasis that possibility.
# TODO: implement post.update with db.update_item in a Ruby-ish way.
#
module DynamodbModel
  class Item
    include DbConfig

    def initialize(attrs={})
      @attrs = attrs
    end

    # Defining our own reader so we can do a deep merge if user passes in attrs
    def attrs(*args)
      case args.size
      when 0
        ActiveSupport::HashWithIndifferentAccess.new(@attrs)
      when 1
        attributes = args[0] # Hash
        if attributes.empty?
          ActiveSupport::HashWithIndifferentAccess.new
        else
          @attrs = attrs.deep_merge!(attributes)
        end
      end
    end

    # Not using method_missing to allow usage of dot notation and assign
    # @attrs because it might hide actual missing methods errors.
    # DynamoDB attrs can go many levels deep so it makes less make sense to
    # use to dot notation.

    # The method is named replace to clearly indicate that the item is
    # fully replaced.
    def replace
      attrs = self.class.replace(@attrs)
      @attrs = attrs # refresh attrs because it now has the id
    end

    def find(id)
      self.class.find(id)
    end

    def table_name
      self.class.table_name
    end

    def partition_key
      self.class.partition_key
    end

    def to_attrs
      @attrs
    end

    # Longer hand methods for completeness.
    # Internallly encourage the shorter attrs method.
    def attributes=(attributes)
      @attributes = attributes
    end

    def attributes
      @attributes
    end

    # AWS Docs examples: http://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GettingStarted.Ruby.04.html
    # Usage:
    #
    #   Post.scan(
    #     expression_attribute_names: {"#updated_at"=>"updated_at"},
    #     filter_expression: "#updated_at between :start_time and :end_time",
    #     expression_attribute_values: {
    #       ":start_time" => "2010-01-01T00:00:00",
    #       ":end_time" => "2020-01-01T00:00:00"
    #     }
    #   )
    #
    # TODO: pretty lame interface, improve it somehow. Maybe:
    #
    #   Post.scan(filter: "updated_at between :start_time and :end_time")
    #
    # which automatically maps the structure.
    def self.scan(params={})
      puts("Should not use scan for production. It's slow and expensive. You should create either a LSI or GSI and use query the index instead.")

      defaults = {
        table_name: table_name
      }
      params = defaults.merge(params)
      resp = db.scan(params)
      resp.items.map {|i| Post.new(i) }
    end

    def self.replace(attrs)
      # Automatically adds some attributes:
      #   partition key unique id
      #   created_at and updated_at timestamps. Timestamp format from AWS docs: http://amzn.to/2z98Bdc
      defaults = {
        partition_key => Digest::SHA1.hexdigest([Time.now, rand].join)
      }
      item = defaults.merge(attrs)
      item["created_at"] ||= Time.now.utc.strftime('%Y-%m-%dT%TZ')
      item["updated_at"] = Time.now.utc.strftime('%Y-%m-%dT%TZ')

      # put_item full replaces the item
      resp = db.put_item(
        table_name: table_name,
        item: item
      )

      # The resp does not contain the attrs. So might as well return
      # the original item with the generated partition_key value
      item
    end

    def self.find(id)
      resp = db.get_item(
        table_name: table_name,
        key: {partition_key => id}
      )
      attributes = resp.item # unwraps the item's attributes
      Post.new(attributes) if attributes
    end

    # Two ways to use the delete method:
    #
    # 1. Specify the key as a String. In this case the key will is the partition_key
    # set on the model.
    #   MyModel.delete("728e7b5df40b93c3ea6407da8ac3e520e00d7351")
    #
    # 2. Specify the key as a Hash, you can arbitrarily specific the key structure this way
    # MyModel.delete("728e7b5df40b93c3ea6407da8ac3e520e00d7351")
    #
    # options is provided in case you want to specific condition_expression or
    # expression_attribute_values.
    def self.delete(key_object, options={})
      if key_object.is_a?(String)
        key = {
          partition_key => key_object
        }
      else # it should be a Hash
        key = key_object
      end

      params = {
        table_name: table_name,
        key: key
      }
      # In case you want to specify condition_expression or expression_attribute_values
      params = params.merge(options)

      resp = db.delete_item(params)
    end

    # When called with an argument we'll set the internal @partition_key value
    # When called without an argument just retun it.
    # class Comment < DynamodbModel::Item
    #   partition_key "post_id"
    # end
    def self.partition_key(*args)
      case args.size
      when 0
        @partition_key || "id" # defaults to id
      when 1
        @partition_key = args[0].to_s
      end
    end

    def self.table_name
      @table_name = self.name.pluralize.underscore
      [table_namespace, @table_name].reject {|s| s.nil? || s.empty?}.join('-')
    end
  end
end
