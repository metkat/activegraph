class Neo4j::ActiveModel

  class << self
    alias_method :orig_new, :new
  end

  include Neo4j::NodeMixin
  extend ActiveModel::Naming
  include ActiveModel::Validations
  include ActiveModel::Dirty

  class RecordInvalidError < RuntimeError
    attr_reader :record

    def initialize(record)
      @record = record
      super(@record.errors.full_messages.join(", "))
    end
  end

  def init_on_create(*props)
    # :nodoc:
    @_java_node = Neo4j::Node.new(*props)
    @_new_record = true
    self[:_classname] = self.class.name
  end

  # --------------------------------------
  #
  # --------------------------------------

  def id
    self.neo_id
  end

  def method_missing(method_id, *args, &block)
    if !self.class.attribute_methods_generated?
      self.class.define_attribute_methods(self.class.properties_info.keys)
      # try again
      send(method_id, *args, &block)
    end
  end

  # redefine this methods so that ActiveModel::Dirty will work
  def []=(key, new_value)
    key = key.to_s
    unless key[0] == ?_
      old_value = self.send(:[], key)
      attribute_will_change!(key) unless old_value == new_value
      #changed_attributes[key] = new_value unless old_value == new_value
    end
    super
  end

  def attribute_will_change!(attr)
    begin
      value = __send__(:[], attr)
      value = value.duplicable? ? value.clone : value
    rescue TypeError, NoMethodError
    end
    changed_attributes[attr] = value
  end


  def read_attribute_for_validation(key)
    self[key]
  end

  def attributes=(attrs)
    attrs.each do |k, v|
      if respond_to?("#{k}=")
        send("#{k}=", v)
      else
        self[k] = v
      end
    end
  end

  def update_attributes(attributes)
    self.attributes = attributes
    save
  end

  def delete
    super
    @_deleted = true
  end

  def save
    @previously_changed = changes
    @changed_attributes.clear
    if valid?
      # if we are trying to save a value then we should create a real node
      unless persisted?
        node = Neo4j::Node.new(props)
        init_on_load(node)
        init_on_create
      end
      true
    end
  end

  # In neo4j all object are automatically persisted in the database when created (but the Transaction might get rollback)
  # Only the Neo4j::Value object will never exist in the database
  def persisted?
    !_java_node.kind_of?(Neo4j::Value)
  end

  def save!
    raise RecordInvalidError.new(self) unless save
  end

  def to_model
    self
  end

  def new_record?()
    @_new_record
  end

  def del
    @_deleted = true
    super
  end

  def destroy
    del
  end

  def destroyed?()
    @_deleted
  end


  # --------------------------------------
  # Class Methods
  # --------------------------------------

  class << self
    # returns a value object instead of creating a new node
    def new(*args)
      value = Neo4j::Value.new(*args)
      wrapped = self.orig_new
      wrapped.init_on_load(value)
      wrapped
    end


    # Handle Model.find(params[:id])
    def find(*args)
      if args.length == 1 && String === args[0] && args[0].to_i != 0
        load(*args)
      else
        super
      end
    end

    def load(*ids)
      result = ids.map { |id| Neo4j::Node.load(id) }
      if ids.length == 1
        result.first
      else
        result
      end
    end

  end

end


#class LintTest < ActiveModel::TestCase
#  include ActiveModel::Lint::Tests
#
#  class MyModel
#    include Neo4j::NodeMixin
#  end
#
#  def setup
#    @model = MyModel.new
#  end
#
#end
#
#require 'test/unit/ui/console/testrunner'
#Neo4j::Transaction.run do
#  Test::Unit::UI::Console::TestRunner.run(LintTest)
#end
