
require 'spec'
require 'lib/string_stream'
require 'lib/data_format'

describe DataFormat do

	it "should read primitive" do
		stream = StringStream.create(10)
		pc = DataFormat::NumberSerializer.new(:uint)
		
		pc.read(stream).should == 10
	end

	it "should read primitive and store value in object" do
		stream = StringStream.create(10)
		pc = DataFormat::NumberSerializer.new(:uint,:attribute => 'size', :object => Struct.new(:size).new)
		pc.read(stream).should == 10
		pc.object.size.should == 10
	end

	it "should create format of primitives" do
		stream = StringStream.create(1337,-0.1337)
		
		d = DataFormat.description do
			int :the_id
			float :value
		end

		data = d.read_from(stream)
		data.the_id.should == 1337
		data.value.should == [-0.1337].pack("g").unpack("g").first
	end

	it "simple format" do
		stream = StringStream.create("asd\0",1337,-0.1337)

		d = DataFormat.description do
			string :name
			uint :int_value
			float :float_value
		end

		data = d.read_from(stream)
		data.name.should == "asd"
		data.int_value.should == 1337
		data.float_value.should == [-0.1337].pack("g").unpack("g").first
	end

	it "simple format with options" do
		stream = StringStream.create("asdfghjk",2,0.225)

		d = DataFormat.description do
			string :name, :length => 8
			uint :int_value, :min => 1, :max => 100
			float :float_value, :min => 0.0, :max => 1.0
		end

		data = d.read_from(stream)
		data.name.should == "asdfghjk"
		data.int_value.should == 2
		data.float_value.should == [0.225].pack("g").unpack("g").first
	end

	it "should validate data" do
		stream = StringStream.create(0,-0.5)

		d = DataFormat.description do
			uint :int_value, :min => 1, :max => 100
			float :float_value, :min => 0.0, :max => 1.0
		end
		
		data = d.read_from(stream)
		
		d.root_serializer[:int_value].errors.should include("min")
		d.root_serializer[:float_value].errors.should include("min")
	end

	it "should validate magic number and raise" do
		stream = StringStream.create(0)

		d = DataFormat.description do
			# magic 1337
			magic :magic_number, :value => 1337
		end

		lambda{d.read_from(stream)}.should raise_error(DataFormat::MagicSerializer::MagicStringError)
	end

	it "should validate magic string and pass" do
		stream = StringStream.create("1337")

		d = DataFormat.description do
			magic :magic_number, :value => "1337"
		end

		lambda{d.read_from(stream)}.should_not raise_error
	end

	it "should read an array" do
		stream = StringStream.create("str\0",2,4363,0.5,66584,-1677.5)
		
		d = DataFormat.description do
			string :name
			uint :arr_length

			array(:things,:length => :arr_length) do
				int :thing_id
				float :value
			end
		end

		data = d.read_from(stream)
		
		data.name.should == "str"
		
		data.arr_length.should == 2
		data.things[0].thing_id.should == 4363
		data.things[0].value.should == 0.5

		data.things[1].thing_id.should == 66584
		data.things[1].value.should == -1677.5
	end

	it "should read an object from string" do
		stream = StringStream.create("the name\0",100,2,"yes\0","no\0")
		class ItemList
			attr_accessor :name, :max_size, :items
		end

		class Item
			attr_accessor :value
		end

		item_cls = Item # FIXME ugly but seems necessary in ruby 1.9

		d = DataFormat.description do
			string :name
			uint :max_size

			array(:items,:class => item_cls) do
				string :value
			end
		end

		data = d.read_from(stream,:object => ItemList.new)

		data.class.should == ItemList
		data.items[0].class.should == Item
		data.items[0].value.should == "yes"
		data.items[1].class.should == Item
		data.items[1].value.should == "no"
	end
end

