# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/dictionary'
require 'hexapdf/reference'

describe HexaPDF::Dictionary do
  def deref(obj)
    if obj.kind_of?(HexaPDF::Reference)
      HexaPDF::Object.new('deref', oid: obj.oid, gen: obj.gen)
    else
      obj
    end
  end

  def add(obj)
    HexaPDF::Object.new(obj, oid: 1)
  end

  def delete(_obj)
  end

  def wrap(obj, type:)
    type.new(obj, document: self)
  end

  before do
    @test_class = Class.new(HexaPDF::Dictionary)
    @test_class.define_field(:Boolean, type: [TrueClass, FalseClass], default: false, version: '1.3')
    @test_class.define_field(:Array, type: Array, required: true, default: [])
    @test_class.define_field(:TestClass, type: @test_class, indirect: true)

    @dict = @test_class.new({Array: [3, 4], Other: 5, Object: HexaPDF::Object.new(:obj)},
                            document: self)
  end

  describe "class methods" do
    it "allows defining fields and retrieving their info" do
      field = @test_class.field(:Boolean)
      refute_nil(field)
      assert_equal('1.3', field.version)
      assert_equal(false, field.default)
      refute(field.required?)

      field = @test_class.field(:Array)
      assert(field.required?)
      assert_equal([], field.default)

      assert(@test_class.field(:TestClass).indirect)
    end

    it "can retrieve fields from parent classes" do
      @inherited_class = Class.new(@test_class)

      assert(@inherited_class.field(:Boolean))
      refute(@inherited_class.field(:Unknown))
    end

    it "can iterate over all fields" do
      @inherited_class = Class.new(@test_class)
      @inherited_class.define_field(:Inherited, type: [Array, Symbol])
      assert_equal([:Boolean, :Array, :TestClass, :Inherited], @inherited_class.each_field.map {|k, _| k})
    end

    it "allows field access without subclassing" do
      refute(HexaPDF::Dictionary.field(:Test))
      assert_equal([], HexaPDF::Dictionary.each_field.to_a)
    end
  end

  describe "after_data_change" do
    it "fails if the value is not a hash" do
      assert_raises(HexaPDF::Error) { HexaPDF::Dictionary.new(:Name) }
    end

    it "sets the default value for a required field that has one" do
      @test_class.define_field(:Type, type: Symbol, required: true, default: :MyType)
      obj = @test_class.new(nil)
      assert_equal(:MyType, obj.value[:Type])
    end
  end

  describe "[]" do
    it "allows retrieving set field values" do
      assert_equal([3, 4], @dict[:Array])
      assert_equal(5, @dict[:Other])
    end

    it "uses a default value if no value is set" do
      assert_equal(false, @dict[:Boolean])
      @dict.value[:Boolean] = true
      assert_equal(true, @dict[:Boolean])
    end

    it "resolves references and stores the resolved object in place of the reference" do
      @dict[:value] = HexaPDF::Reference.new(1, 0)
      assert_equal('deref', @dict[:value])
      assert_kind_of(HexaPDF::Object, @dict.value[:value])
    end

    it "wraps hash values in specific subclasses" do
      @dict.value[:TestClass] = {Array: [1, 2]}
      assert_kind_of(@test_class, @dict[:TestClass])
      assert_equal([1, 2], @dict[:TestClass][:Array])

      @dict.value[:TestClass] = HexaPDF::Object.new([1, 2])
      refute_kind_of(@test_class, @dict[:TestClass])
      assert_equal([1, 2], @dict[:TestClass])
    end

    it "fetches the value out of a HexaPDF::Object" do
      assert_equal(:obj, @dict[:Object])
    end

    it "can convert data even if it is inside a HexaPDF::Object" do
      @test_class.define_field(:Binary, type: HexaPDF::DictionaryFields::PDFByteString)
      @dict[:Binary] = HexaPDF::Object.new('test')
      result = @dict[:Binary]
      assert_equal('test', result)
      assert_equal(Encoding::BINARY, result.encoding)
      assert_kind_of(HexaPDF::Object, @dict.value[:Binary])
      assert_same(result, @dict.value[:Binary].value)
    end
  end

  describe "[]=" do
    it "directly stores the value if the stored value is no HexaPDF::Object" do
      @dict[:Array] = [4, 5]
      assert_equal([4, 5], @dict.value[:Array])

      @dict[:NewValue] = 7
      assert_equal(7, @dict.value[:NewValue])
    end

    it "stores the value inside the current value HexaPDF::Object but only if the given one is not such an object" do
      @dict[:Object] = [4, 5]
      assert_equal([4, 5], @dict.value[:Object].value)

      @dict[:Object] = temp = HexaPDF::Object.new(:other)
      assert_equal(temp, @dict.value[:Object])
    end

    it "doesn't store the value inside for subclasses of HexaPDF::Object" do
      (@dict[:TestClass] ||= {})[:Array] = [4, 5]
      assert_kind_of(@test_class, @dict[:TestClass])
      @dict[:TestClass] = [4, 5]
      assert_equal([4, 5], @dict[:TestClass])
    end

    it "doesn't store the value inside for HexaPDF::Reference objects" do
      @dict[:Object] = HexaPDF::Object.new(:test)
      assert_kind_of(HexaPDF::Object, @dict.value[:Object])
      @dict[:Object] = HexaPDF::Reference.new(5, 0)
      assert_kind_of(HexaPDF::Reference, @dict.value[:Object])
    end

    it "raises an error if the key is not a symbol object" do
      assert_raises(HexaPDF::Error) { @dict[5] = 6 }
    end
  end

  describe "validate_fields" do
    before do
      @test_class.define_field(:Inherited, type: [Array, Symbol], required: true, indirect: false)
      @obj = @test_class.new({Array: [], Inherited: :symbol}, document: self)
    end

    it "checks for the required fields w/wo auto_correct" do
      assert(@obj.validate(auto_correct: false))
      assert_equal({Array: [], Inherited: :symbol}, @obj.value)

      @obj.value.delete(:Array)
      refute(@obj.validate(auto_correct: false))
      assert(@obj.validate(auto_correct: true))
      assert_equal({Array: [], Inherited: :symbol}, @obj.value)

      @obj.value.delete(:Inherited)
      refute(@obj.validate(auto_correct: true))
    end

    it "checks for the correct type of a set field" do
      @obj.value[:Inherited] = 'string'
      refute(@obj.validate(auto_correct: false))

      @obj.value[:Inherited] = HexaPDF::Object.new(:symbol)
      assert(@obj.validate(auto_correct: false))

      @obj.value[:Inherited] = Class.new(Array).new([5])
      assert(@obj.validate(auto_correct: false))
    end

    it "checks whether a field needs to be indirect w/wo auto_correct" do
      @obj.value[:Inherited] = HexaPDF::Object.new(:test, oid: 1)
      refute(@obj.validate(auto_correct: false))
      assert(@obj.validate(auto_correct: true))
      assert_equal(:test, @obj.value[:Inherited])

      @obj.value[:TestClass] = {Inherited: :symbol}
      refute(@obj.validate(auto_correct: false))
      assert(@obj.validate(auto_correct: true))
      assert_equal(1, @obj.value[:TestClass].oid)

      @obj.value[:TestClass] = HexaPDF::Object.new(Inherited: :symbol)
      assert(@obj.validate(auto_correct: true))
      assert_equal(1, @obj.value[:TestClass].oid)
    end

    it "validates values that are PDF objects" do
      @obj.value[:TestClass] = @test_class.new(nil, document: self)
      refute(@obj.validate)
      @obj.value[:TestClass][:Inherited] = :symbol
      assert(@obj.validate)
    end

    it "validates direct PDF objects nested in hashes" do
      @obj[:TestClass] = {Inherited: :symbol, Nested: {Nested: {TestClass: @test_class.new(nil, document: self)}}}
      refute(@obj.validate)
      @obj[:TestClass][:Nested][:Nested][:TestClass][:Inherited] = :symbol
      assert(@obj.validate)
    end
  end

  describe "delete" do
    it "deletes an entry from the underlying hash value and returns its value" do
      assert_equal(5, @dict.delete(:Other))
      refute(@dict.value.key?(:Other))
    end

    it "returns nil if no entry with the given name exists" do
      assert_nil(@dict.delete(:SomethingUnknown))
    end
  end

  describe "each" do
    it "iterates over all name-value pairs in the dictionary" do
      @dict[:TestClass] = {}
      data = [:Array, [3, 4], :Other, 5, :Object, :obj, :TestClass, @dict[:TestClass]]
      @dict.each do |name, value|
        assert_equal(data.shift, name)
        assert_equal(data.shift, value)
      end
    end
  end

  describe "to_hash" do
    it "returns a shallow copy of the value" do
      obj = @dict.to_hash
      refute_equal(obj.object_id, @dict.value.object_id)
      assert_equal(obj, @dict.value)
    end
  end

  describe "type" do
    it "returns the /Type entry" do
      @dict[:Type] = :Test
      assert_equal(:Test, @dict.type)
    end

    it "returns the value from Object#type if not /Type entry is present" do
      assert_equal(:Unknown, @dict.type)
    end
  end

  describe "empty?" do
    it "returns true if the dictionary contains no entries" do
      assert(HexaPDF::Dictionary.new({}).empty?)
      refute(HexaPDF::Dictionary.new(x: 5).empty?)
    end
  end
end