# frozen_string_literal: true

module NeedhamCircle
  class Form
    class Field
      attr_reader :name #: Symbol

      #: (Symbol name, String human) -> void
      def initialize(name, human)
        @name = name
        @human = human
      end
    end

    class StringField < Field
      #: (Symbol name, String human, ?required: bool, ?max_length: Integer?, ?nullify: bool) -> void
      def initialize(name, human, required: false, max_length: nil, nullify: false)
        super(name, human)
        @required = required
        @max_length = max_length
        @nullify = nullify
      end

      #: (String? value) -> String
      def coerce(value)
        value = String(value).strip
        value = nil if @nullify && value.empty?
        value
      end

      #: (String value) -> String?
      def validate(value)
        return "#{@human} is required." if @required && value.empty?
        return "#{@human} must be at most #{@max_length} characters." if @max_length && value.length > @max_length
        nil
      end
    end

    class TimeField < Field
      #: (Symbol name, String human, ?required: bool, ?future_only: bool) -> void
      def initialize(name, human, required: false, future_only: false)
        super(name, human)
        @required = required
        @future_only = future_only
      end

      #: (String value) -> Time?
      def coerce(value)
        value && Time.strptime(value, "%Y-%m-%dT%H:%M")
      rescue ArgumentError
      end

      #: (Time? value) -> String?
      def validate(value)
        return "#{@human} is required to be a valid time." if @required && value.nil?
        return "#{@human} must be in the future." if @future_only && value <= Time.now
        nil
      end
    end

    class URLField < Field
      #: (Symbol name, String human, ?required: bool, ?max_length: Integer?) -> void
      def initialize(name, human, required: false, max_length: nil)
        super(name, human)
        @required = required
        @max_length = max_length
      end

      #: (String? value) -> String
      def coerce(value)
        String(value).strip
      end

      #: (String value) -> String?
      def validate(value)
        return "#{@human} is required." if @required && value.empty?
        return "#{@human} must be at most #{@max_length} characters." if @max_length && value.length > @max_length
        return "#{@human} must be a valid URL." if !value.empty? && !(value =~ /\Ahttps:\/\/.*\z/)
        nil
      end
    end

    class MultiSelectField < Field
      attr_reader :values #: Array[String]

      #: (Symbol name, String human, values: Array[String]) -> void
      def initialize(name, human, values:)
        super(name, human)
        @values = values
      end

      # Splits the comma-joined param and keeps only known values, preserving
      # the declared option order so the selection is stable.
      #: (String? value) -> Array[String]
      def coerce(value)
        selected = String(value).split(",")
        @values.select { |allowed| selected.include?(allowed) }
      end

      #: (Array[String] value) -> String?
      def validate(value)
        nil
      end
    end

    attr_reader :values #: Hash[Symbol, String]
    attr_reader :coerced #: Hash[Symbol, untyped]
    attr_reader :errors #: Hash[Symbol, Array[String]]

    #: (?Hash[String, String] params) -> void
    def initialize(params = default = {})
      @values = {}
      @coerced = {}
      @errors = Hash.new { |hash, key| hash[key] = [] }

      self.class.fields.each do |field|
        value = @values[field.name] = params.fetch(field.name.name, "")
        @coerced[field.name] = field.coerce(value)
      end

      return if default

      self.class.fields.each do |field|
        if (error = field.validate(@coerced[field.name]))
          @errors[field.name] << error
        end
      end

      self.class.validations.each do |validation|
        validation.call(self)
      end
    end

    #: (Symbol name) -> String
    def value_for(name)
      @values[name]
    end

    #: (Symbol name) -> untyped
    def coerced_for(name)
      @coerced[name]
    end

    #: (Symbol name) -> Array[String]
    def errors_for(name)
      @errors[name]
    end

    #: () -> bool
    def valid?
      @errors.values.all?(&:empty?)
    end

    class << self
      #: () -> Array[Field]
      def fields
        @fields ||= []
      end

      #: (Field value) -> void
      def field(value)
        fields << value
      end

      #: (Symbol name, String human, **options) -> void
      def multi_select_field(name, human, **options)
        field MultiSelectField.new(name, human, **options)
      end

      #: (Symbol name, String human, **options) -> void
      def string_field(name, human, **options)
        field StringField.new(name, human, **options)
      end

      #: (Symbol name, String human, **options) -> void
      def time_field(name, human, **options)
        field TimeField.new(name, human, **options)
      end

      #: (Symbol name, String human, **options) -> void
      def url_field(name, human, **options)
        field URLField.new(name, human, **options)
      end

      #: () -> Array[Proc]
      def validations
        @validations ||= []
      end

      #: () { (Form) -> void } -> void
      def validate(&block)
        validations << block
      end
    end
  end
end
