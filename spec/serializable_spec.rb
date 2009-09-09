
require 'spec'
require 'lib/string_stream'
require 'lib/serializable'

describe Serializable do

	class SomeObject
		include Serializable

		attr_accessor :name, :size

		self.default_data_format_name = :legacy

		data_format(:legacy) do
			string :name
			uint :size
		end

		data_format(:modern) do
			string :name, :length => 8
			uint :size
		end
	end

	it "should have default format" do
		SomeObject.data_formats.keys.should include(:legacy)
		SomeObject.default_data_format_name.should == :legacy
		SomeObject.default_data_format.should == SomeObject.data_formats[:legacy]
	end

	it "should have other formats" do
		SomeObject.data_formats.keys.should include(:modern)
	end

	it "should load from :legacy stream" do
		stream = StringStream.create("legacyfile\0",13378)
		
		obj = SomeObject.load_from(stream)

		obj.class.should == SomeObject
		obj.name.should == "legacyfile"
		obj.size.should == 13378
	end

	it "should load from :modern stream" do
		stream = StringStream.create("12345678",13378)

		obj = SomeObject.load_from(stream,:modern)

		obj.class.should == SomeObject
		obj.name.should == "12345678"
		obj.size.should == 13378
	end
end

