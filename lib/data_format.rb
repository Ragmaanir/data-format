require 'ostruct'

# 
module DataFormat

	def self.description(name=nil,&block)
		Builder.new(name,&block).data_format
	end

	class DataFormat
		attr_accessor :root_serializer

		def initialize(name=nil)
			self.root_serializer = RootSerializer.new
		end

		def read_from(stream,options={})
			root_serializer.object = options[:object] if options[:object]
			root_serializer.read(stream)
			result = root_serializer.object
			root_serializer.clean
			result
		end
	end

	#
	class Serializer
		attr_accessor :type, :options
		attr_accessor :object, :attribute, :errors

		def initialize(type,options={})
			self.type = type
			self.object = options.delete :object
			self.attribute = options.delete(:attribute).to_s
			self.options = options || {}
			self.errors = []
		end

		def assign_to_attribute(value)
			if object
				#raise "object #{object} does not respond to '#{attribute}='" unless object.respond_to? "#{attribute}="
				object.send("#{attribute}=",value)
			end
		end

		def clean
			self.object = nil
		end
	end

	#
	class PrimitiveSerializer < Serializer
		
	end

	# 
	class NumberSerializer < PrimitiveSerializer
		Names = [:short,:int,:long,:float,:double]
		Keywords = Names+Names.collect{|n| "u#{n}".to_sym }
		Sizes = {:short => 2, :int => 4, :long => 8, :float => 4, :double => 8}
		Integers = [:short,:int,:long]

		attr_accessor :size, :signed

		def byte_order
			options[:byte_order] || :big_endian
		end

		def big_endian?
			byte_order == :big_endian
		end

		def little_endian?
			byte_order == :little_endian
		end

		def signed?
			self.signed
		end

		def integer?
			Integers.member? self.type
		end

		def self.bytes_of_type(type)
			PrimitiveSerializer.type_without_unsigned_letter(type)
		end

		# Returns a type(symbol) with the unsigned-indication letter removed
		# :uint => :int
		# :int => :int
		def self.type_without_unsigned_letter(type)
			type.to_s.sub(/\Au/,"").to_sym
		end

		def self.is_signed_type?(type)
			type.to_s[0] == "u"
		end

		def type=(type)
			basic_type = NumberSerializer.type_without_unsigned_letter(type)
			if Names.member?(basic_type)
				@type = basic_type
				self.size = Sizes[basic_type]
				self.signed = NumberSerializer.is_signed_type?(type)
			else
				@type = :float
				self.size = Sizes[type]
			end
		end

		def validate(value)
			# FIXME dont store errors in the serializer
			errors << "min" if options[:min] and value < options[:min]
			errors << "max" if options[:max] and value > options[:max]
		end
		
		def read(stream)
			if integer?
				values = stream.readbytes(size).unpack("C*")
				values.reverse! if big_endian? # convert to little endian

				# construct an integer value from bytes in little endian byte order
				value = 0
				values.each_with_index { |v,i| value += v << i*8 }
			else # float or double
				packer = big_endian? ? 'g' : 'e'
				packer.upcase! if type == :double
				value = stream.readbytes(size).unpack(packer).first
			end
			
			validate(value)
			assign_to_attribute(value)
			value
		end
	end

	# options:
	# - :length: the number of bytes to be read from the stream.
	#		when nil then the string is assumed to be null-terminated.
	class StringSerializer < PrimitiveSerializer
		Keywords = [:string]

		def read(stream)
			if options[:length]
				string = stream.readbytes(options[:length])
			else
				string = stream.readline('\0')[0...-1]
			end

			assign_to_attribute(string)
			string
		end
	end

	# 
	class MagicSerializer < PrimitiveSerializer
		Keywords = [:magic]

		class MagicStringError < RuntimeError; end

		attr_accessor :magic_value

		def initialize(type,options={})
			self.type = type
			self.magic_value = options[:value]
			self.options = options || {}
			self.errors = []
		end

		def read(stream)
			if magic_value.is_a? String
				value = stream.readbytes(magic_value.length)
			elsif magic_value.is_a? Integer
				value = NumberSerializer.new(:uint).read(stream)
			end
			raise MagicStringError,"magic number mismatch: should be '#{magic_value}' but was '#{value}'" unless magic_value == value
		end
	end

	#
	class ComplexSerializer < Serializer
		attr_accessor :serializers

		def [](attr)
			serializers.find { |s| s.attribute == attr.to_s }
		end

		def << serializer
			raise "duplicate serializer #{serializer.attribute}" if self[serializer.attribute]
			serializers << serializer
		end

		def clean
			serializers.each {|s| s.clean }
			super
		end
	end

	#
	class RootSerializer < ComplexSerializer
		def initialize
			self.serializers ||= []
		end

		def read(stream)
			self.object ||= (type || OpenStruct).new
			serializers.each do |s|
				s.object = object
				s.read(stream)
			end

			object
		end
	end

	# options:
	# - :length: the length of the array.
	#		when a symbol then the attribute identified vby this symbol will be read of the object to load.
	#		when nil then read the length from stream (see :length_field_type).
	# - :class: the class of each entry.
	#		when a class then instantiate the class and assign the values read from stream to the attributes of the instance.
	#		when nil then instantiate an OpenStruct and store the values in it.
	# - :length_field_type: when no array length is given, then the array length is read from the stream via a NumberSerializer.
	#		the type read from the stream can be set by this parameter. it is passed to the constructor of the NumberSerializer.
	class ArraySerializer < ComplexSerializer
		Keywords = [:array]

		def initialize(*args,&block)
			super(*args)
			self.serializers = Builder.new(&block).data_format.root_serializer.serializers# XXX use builder here or pass the serializers from outside?
		end

		def read(stream)
			# determine length of the array
			if options[:length]
				# if length is a symbol, read the value of the attribute the symbol identifies
				options[:length] = object.send(options[:length]) if options[:length].is_a? Symbol
			else
				# no length given, so the length must be read from the stream
				options[:length] = NumberSerializer.new(options[:length_field_type] || :uint).read(stream)
			end

			arr = []

			options[:length].times do
				entry = (options[:class] || OpenStruct).new # create the instance for the current entry
				serializers.each do |s|
					s.object = entry
					s.read(stream)
				end
				arr << entry
			end

			assign_to_attribute(arr)
			arr
		end
	end

	# 
	class Builder

		DefaultSerializers = [NumberSerializer,StringSerializer,ArraySerializer,MagicSerializer]

		attr_accessor :data_format
		attr_accessor :available_serializers

		def initialize(options={},&block)
			self.data_format = DataFormat.new
			self.available_serializers = DefaultSerializers
			instance_eval(&block)
		end
		
		def method_missing(meth,*args,&block)
			serializer = available_serializers.find{|ab| ab::Keywords.member? meth} || raise("no serializer found for '#{meth}'")
			options = {:attribute => args.first}.merge!(args[1] || {})
			data_format.root_serializer << serializer.new(meth,options,&block)
			# return an object that can be used to add validation or evaluation blocks to the serializer
		end
	end

end
