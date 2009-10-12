
require 'spec'
require 'binary_size'

describe BinarySize do

	it "should be bits" do
		3.bits.should be_bits
	end

	it "should be bytes" do
		55.bytes.should be_bytes
	end

	it "should be MB" do
		128.mb.should be_mb
	end

	it "should calculate size of 1 MB" do
		1.mb.should == (1024*1024*8).bits
	end

	it "should be comparable" do
		8.bits.should == 1.bytes
		1024.bytes.should == 1.kb
		1024.kb.should == 1.mb
	end

	it "should be addable" do
		(5.bits + 3.bits).should == 1.bytes
		(2.bytes + 16.bits).should == 4.bytes
	end

	it "should not be addable with integers" do
		expect{5+3.bytes}.to raise_error
		expect{3.bytes+5}.to raise_error
	end

	it "should calculate bits, bytes, kbs, etc" do
		10.bits.to_bytes.should == 10/8.to_f
		1.kb.to_kb.should == 1
		13.mb.to_bits.should == 13*1024*1024*8
		1.bits.to_kb.should == 1/(8*1024).to_f
	end

end