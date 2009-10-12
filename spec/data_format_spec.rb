
require 'spec'
require 'lib/string_stream'
require 'lib/data_format'

describe DataFormat do

	it "should read primitive" do
		stream = StringStream.create(10)
		object = OpenStruct.new
		context = DataFormat::SerializationContext.new(:read,object,stream)
		pc = DataFormat::IntegerSerializer.new(context)

		pc.read(:uint,:attr,4.bytes).should == 10
	end

	it "should read primitive and store value in object" do
		stream = StringStream.create(10)
		object = OpenStruct.new
		context = DataFormat::SerializationContext.new(:read,object,stream)
		pc = DataFormat::IntegerSerializer.new(context)

		pc.read(:uint,:attr,4.bytes).should == 10
		object.attr.should == 10
	end

	it "should create an empty format" do
		d = DataFormat.description("empty-format") do

		end

		d.name.should == "empty-format"
	end

	it "should create a simple format of primitives and read it from a stream" do
		stream = StringStream.create(1337,-0.1337)
		
		d = DataFormat.description do
			int :the_id
			float :value
		end

		data = d.read_from(stream)
		
		data.the_id.should == 1337
		data.value.should == [-0.1337].pack("g").unpack("g").first
	end

	it "should read a null-terminated string from stream" do
		stream = StringStream.create("asd\0")

		d = DataFormat.description do
			string	:name
		end

		data = d.read_from(stream)
		data.name.should == "asd"
	end
	
	it "should read a fixed-length string from stream" do
		stream = StringStream.create("asdasd")

		d = DataFormat.description do
			string	:name, length: 6.bytes
		end

		data = d.read_from(stream)
		data.name.should == "asdasd"
	end

	it "should read a string from stream with the length stored in the stream" do
		stream = StringStream.create(6,"asdasd")

		d = DataFormat.description do
			int :str_length
			string	:name, length: str_length.bytes
		end

		data = d.read_from(stream)
		data.name.should == "asdasd"
	end


	it "should read various values" do
		stream = StringStream.create("asd\0",1337,-0.1337)

		d = DataFormat.description do
			string	:name
			int			:int_value
			float		:float_value
		end

		data = d.read_from(stream)
		data.name.should == "asd"
		data.int_value.should == 1337
		data.float_value.should == [-0.1337].pack("g").unpack("g").first
	end

	it "simple format with options" do
		stream = StringStream.create("asdfghjk",2,0.225)

		d = DataFormat.description do
			string	:name, length: 8.bytes
			int			:int_value, range: 1..100
			float		:float_value, range: 0.0..1.0
		end

		data = d.read_from(stream)
		data.name.should == "asdfghjk"
		data.int_value.should == 2
		data.float_value.should == [0.225].pack("g").unpack("g").first
	end

	it "should validate data" do
		stream = StringStream.create(0,-0.5)

		d = DataFormat.description do
			int			:int_value, range: 1..100
			float		:float_value, range: 0.0..1.0
		end
		
		expect{ d.read_from(stream) }.to raise_error(DataFormat::MalformedFileError)
	end

	it "should validate magic number and raise" do
		stream = StringStream.create(0)

		d = DataFormat.description do
			magic "1337"
		end

		expect{ d.read_from(stream) }.to raise_error(DataFormat::MagicMismatchError)
	end

	it "should validate magic string and pass" do
		stream = StringStream.create("1337")

		d = DataFormat.description do
			magic "1337"
		end

		lambda{ d.read_from(stream) }.should_not raise_error
	end

	it "should read an array" do
		stream = StringStream.create("str\0",2,4363,0.5,66584,-1677.5)
		
		d = DataFormat.description do
			string :name
			int :arr_length

			array(:things,length: arr_length) do
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
			attr_accessor :name, :max_size, :arr_len, :items
		end

		class Item
			attr_accessor :value
		end

		item_cls = Item # FIXME ugly but seems necessary in ruby 1.9

		d = DataFormat.description do
			string :name
			int :max_size, 4.bytes
			int :arr_len, 4.bytes

			array(:items, length: arr_len, class: item_cls) do
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

	it "should support conditional elements" do

		d = DataFormat.description do
			int :extra_element?, 4.bytes

			if(extra_element? != 0)
				string :elem
			end
		end

		stream1 = StringStream.create(1,"conditional\0")
		stream2 = StringStream.create(0,"conditional\0")

		data = d.read_from(stream1)
		data.elem.should == "conditional"

		data = d.read_from(stream2)
		data.elem.should be_nil
	end

	it "should describe and load bitmap" do
		d = DataFormat.description("bitmap") do
			BI_RGB = 0
			RLE_8 = 1
			RLE_4 = 2
			BI_BITFIELDS = 3

			magic "BM"
			uint :bfSize
			uint :bfReserved
			uint :bfOffBits

			uint :biSize
			uint :biWidth
			int :biHeight
			int :biPlanes, 2.bytes
			int :biBitCount, 2.bytes
			uint :biCompression, range: 0..3
			uint :biSizeImage
			uint :biXPelsPerMeter
			uint :biYPelsPerMeter
			uint :biClrUsed
			uint :biClrImportant

			if(biCompression == BI_BITFIELDS)
				uint :red_bitmask
				uint :green_bitmask
				uint :blue_bitmask
			end

			#* Wenn biClrUsed=0:
			#      o Wenn biBitCount=1, 4 oder 8: Es folgt eine Farbtabelle mit 2^biBitCount Einträgen.
			#      o Ansonsten: Es folgt keine Farbtabelle.
			#* Ansonsten: Es folgt eine Farbtabelle mit biClrUsed Einträgen.
			if(biClrUsed == 0)
				if([1,4,8].member? biBitCount)
					array(:color_table, length: 2**biBitCount) do
						byte :red
						byte :green
						byte :blue
						byte :zero
					end
				end
			else
				array(:color_table, length: biClrUsed) do
					byte :red
					byte :green
					byte :blue
					byte :zero
				end
			end

			at(bfOffBits) do
				array(:data, length: biCompression == BI_RGB ? biWidth * biHeight * biBitCount/8 : biSizeImage) do
					case biCompression
						when BI_BITFIELDS
						when BI_RGB
							case biBitCount
								when 1,4,8
								when 16
								when 24
								when 32
							end
						when RLE_4
						when RLE_8
					end
				end
			end

			# FIXME implement
			
		end # end format

	end

end

