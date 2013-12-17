module NoBrainer::Document::Attributes
  extend ActiveSupport::Concern

  included do
    if NoBrainer.rails3?
      include ActiveModel::MassAssignmentSecurity
    end
    attr_accessor :attributes

    # Not using class_attribute because we want to
    # use our custom logic
    class << self; attr_accessor :fields; end
    self.fields = {}
  end

  def initialize(attrs={}, options={})
    super
    assign_attributes(attrs, options.reverse_merge(:pristine => true))
  end

  def read_attribute(name)
    __send__("#{name}")
  end
  def [](*args); read_attribute(*args); end

  def write_attribute(name, value)
    __send__("#{name}=", value)
  end
  def []=(*args); write_attribute(*args); end

  def assign_defaults
    self.class.fields.each do |name, options|
      if options.has_key?(:default)
        default_value = options[:default]
        default_value = default_value.call if default_value.is_a?(Proc)
        self.write_attribute(name, default_value)
      end
    end
  end

  def reset_attributes
    # XXX Performance optimization: we don't save field that are not
    # explicitly set. The row will therefore not contain nil for
    # unset attributes.
    self.attributes = {}
    self.assign_defaults
  end

  def assign_attributes(attrs, options={})
    reset_attributes if options[:pristine]

    if options[:from_db]
      # TODO Should we reject undeclared fields ?
      #
      # TODO Should we use the setters?
      # Let's postpone the answer once we have custom types to
      # serialize/deserialize on the database.
      attributes.merge! attrs
    else
      if NoBrainer.rails3? && !options[:without_protection]
        # TODO What's up with rails4?
        attrs = sanitize_for_mass_assignment(attrs, options[:as])
      end
      attrs.each { |k,v| self.write_attribute(k, v) }
    end
  end
  def attributes=(*args); assign_attributes(*args); end

  # TODO test that thing
  def inspect
    attrs = self.class.fields.keys.map { |f| "#{f}: #{attributes[f.to_s].inspect}" }
    "#<#{self.class} #{attrs.join(', ')}>"
  end

  module ClassMethods
    def new_from_db(attrs, options={})
      klass_from_attrs(attrs).new(attrs, options.reverse_merge(:from_db => true)) if attrs
    end

    def inherited(subclass)
      super
      subclass.fields = self.fields.dup
    end

    def field(name, options={})
      name = name.to_sym

      if name.in? NoBrainer::Criteria::Chainable::Where::RESERVED_FIELDS
        raise "Cannot use a reserved field name: #{name}"
      end

      # Using a hash because:
      # - at some point, we want to associate informations with a field (like the type)
      # - it gives us a set for free
      ([self] + descendants).each do |klass|
        klass.fields[name] ||= {}
        klass.fields[name].merge!(options)
      end

      # Using a layer so the user can use super when overriding these methods
      inject_in_layer :attributes, <<-RUBY, __FILE__, __LINE__ + 1
        def #{name}=(value)
          attributes['#{name}'] = value
        end

        def #{name}
          attributes['#{name}']
        end
      RUBY
    end

    def remove_field(name)
      name = name.to_sym

      ([self] + descendants).each do |klass|
        klass.fields.delete(name)
      end

      inject_in_layer :attributes, <<-RUBY, __FILE__, __LINE__ + 1
        undef #{name}=
        undef #{name}
      RUBY
    end

    def has_field?(name)
      !!fields[name.to_sym]
    end
  end
end
