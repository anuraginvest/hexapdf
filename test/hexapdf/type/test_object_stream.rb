# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/type/object_stream'

describe HexaPDF::Type::ObjectStream::Data do
  before do
    @data = HexaPDF::Type::ObjectStream::Data.new("5 [1 2]", [1, 5], [0, 2])
  end

  it "returns the correct [object, oid] pair for a given index" do
    assert_equal([5, 1], @data.object_by_index(0))
    assert_equal([[1, 2], 5], @data.object_by_index(1))
  end

  it "fails if the index is out of bounds" do
    assert_raises(ArgumentError) { @data.object_by_index(5) }
    assert_raises(ArgumentError) { @data.object_by_index(-1) }
  end
end


describe HexaPDF::Type::ObjectStream do
  before do
    @doc = Object.new
    def (@doc).trailer
      @trailer ||= {Encrypt: HexaPDF::Object.new({}, oid: 9)}
    end
    @obj = HexaPDF::Type::ObjectStream.new({}, oid: 1, document: @doc)
  end

  it "correctly parses stream data" do
    @obj.value = {N: 2, First: 8}
    @obj.stream = "1 0 5 2 5 [1 2]"
    data = @obj.parse_stream
    assert_equal([5, 1], data.object_by_index(0))
    assert_equal([[1, 2], 5], data.object_by_index(1))
  end

  it "allows adding and deleting object as well as determining their index" do
    @obj.add_object(5)
    @obj.add_object(7)
    @obj.add_object(9)
    assert_equal(0, @obj.object_index(5))
    assert_equal(1, @obj.object_index(7))
    assert_equal(2, @obj.object_index(9))

    @obj.delete_object(5)
    assert_equal(0, @obj.object_index(9))
    assert_equal(1, @obj.object_index(7))
    assert_equal(nil, @obj.object_index(5))

    @obj.delete_object(7)
    @obj.delete_object(9)
    assert_equal(nil, @obj.object_index(5))
  end

  it "allows writing the objects to the stream" do
    @obj.stream = 'something'
    @obj.add_object(HexaPDF::Object.new(5, oid: 1))
    @obj.add_object(HexaPDF::Object.new(:will_be_deleted, oid: 3, gen: 1))
    @obj.add_object(HexaPDF::Object.new([1, 2], oid: 5))
    @obj.add_object(HexaPDF::Object.new(nil, oid: 7))
    @obj.add_object(@doc.trailer[:Encrypt])

    revision = Object.new
    def revision.object(obj); obj; end
    @obj.write_objects(revision)

    assert_equal(2, @obj.value[:N])
    assert_equal(8, @obj.value[:First])
    assert_equal("1 0 5 2 5 [1 2] ", @obj.stream)
  end

  it "fails validation if gen != 0" do
    assert(@obj.validate(auto_correct: false))
    @obj.gen = 1
    refute(@obj.validate(auto_correct: false) do |msg, correctable|
             assert_match(/invalid generation/, msg)
             refute(correctable)
           end)
  end
end
