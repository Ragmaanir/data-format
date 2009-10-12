
require 'binary_size'

module DataFormat

	class MalformedFileError < RuntimeError; end
	class MagicMismatchError < RuntimeError; end

	class Serializer
		attr_accessor :context

		def initialize(context)
			self.context = context
		end

		def set(attr_name,value)
			context.object.send("#{attr_name}=",value)
		end

		def get(attr_name)
			context.object.send(attr_name)
		end

		def read_from_stream(size)
			raise "size is not an BinarySize" unless size.kind_of? BinarySize
			context.stream.readbytes(size.to_bytes)
		end

		def read_line_from_stream(delimiter)
			context.stream.readline(delimiter)
		end

		def write_to_stream(data)
			context.stream.write(data)
		end
	end

	class NumberSerializer < Serializer
		# [2.bytes] => [2.bytes,{}]
		# [{}] => [4.bytes,{}]
		# [] => [4.bytes,{}]
		# [1.byte,{cool: 1} => [1.byte,{cool: 1}
		def parse_args(args)
			size = 4.bytes
			if args[0].is_a? BinarySize
				size,options = *args
			else
				options = args[0]
			end
			options ||= {}
			[size,options]
		end
	end

	class IntegerSerializer < NumberSerializer
		def read(type,attribute_name,*args)
			size,options = *parse_args(args)
			raise "invalid size: #{size}" unless [8,16,32,64].include? size.to_i

			values = read_from_stream(size).unpack("C*") # FIXME read 5.bits; method read takes x.bits, y.bytes, z.kb
			values.reverse! if options[:byte_order] == :big_endian or context.big_endian? # convert to little endian

			# construct an integer value from bytes in little endian byte order
			# FIXME signed values: extract MSB to determine sign
			value = 0
			values.each_with_index { |v,i| value += v << i*8 }

			options[:range].include?(value) || raise(MalformedFileError) if options[:range]
			options[:validator].call(value) || raise(MalformedFileError) if options[:validator]

			set(attribute_name,value)
		end

		def write(type,attribute_name,*args)
			size,options = *parse_args(args)

			value = get(attribute_name)

			options[:range].include?(value) || raise(MalformedFileError) if options[:range]
			options[:validator].call(value) || raise(MalformedFileError) if options[:validator]

			bytes = (0..size).collect{|i| (value << (8*i)) & 0xFF} # little endian: lowest byte is at array[0]
			bytes.reverse! if options[:byte_order] == :big_endian or context.big_endian?

			write_to_stream(bytes)
		end
	end

	class FloatSerializer < NumberSerializer
		def read(type,attribute_name,*args)
			size,options = *parse_args(args)
			
			raise "invalid size" unless [32,64].include? size.to_i
			#packer = big_endian? ? 'g' : 'e'
			packer = 'e' # little endian
			packer = 'g' if options[:byte_order] == :big_endian or context.big_endian?
			packer.upcase! if size == 8.bytes
			value = read_from_stream(size).unpack(packer).first

			options[:range].include?(value) || raise(MalformedFileError) if options[:range]
			options[:validator].call(value) || raise(MalformedFileError) if options[:validator]

			set(attribute_name,value)
		end

		def write(type,attribute_name,*args)
			size,options = *parse_args(args)
			
			value = get(attribute_name)

			options[:range].include?(value) || raise(MalformedFileError) if options[:range]
			options[:validator].call(value) || raise(MalformedFileError) if options[:validator]

			# FIXME convert

			write_to_stream(value)
		end
	end

	# options:
	# - :length: the number of bytes to be read from the stream.
	#		when nil then the string is assumed to be null-terminated.
	# 1. null-terminated
	# 2. fixed length
	# (skipped because of endianess)3. length-field in front of string (e.g. one byte, so strings have maxlen of 255, byte = 0 => empty string)
	class StringSerializer < Serializer
		def read(type,attribute_name,options={})
			length = options[:length]
			raise "length (#{length.inspect}) is not an BinarySize" if length and not length.kind_of? BinarySize

			if length # fixed length
				value = read_from_stream(length)
			else
				#if options[:embedded] # embedded length
				#	length = read_from_stream(options[:embedded])
				#	value = read_from_stream(length)
				#else # null-terminated
				value = read_line_from_stream('\0')[0...-1]
				#end
			end

			set(attribute_name,value)
		end

		def write(type,attribute_name,size,options={})
			value = get(attribute_name)

			length = options[:length]

			if length # fixed length
				write_to_stream(value)
			else
				#if options[:embedded] # embedded length
				#	write_to_stream(value.length) # TODO write options[:embedded] bytes
				#	write_to_stream(value)
				#else # null-terminated
				write_to_stream(value+'\0')
				#end
			end
		end
	end

	class MagicSerializer < Serializer

		# TODO block as value?

		def read(type,value,options={})
			# TODO move validation of VALUE out into method
			# TODO support INTEGER values
			raise "magic value must be a string" unless value.is_a? String
			magic = read_from_stream(value.length.bytes)
			raise MagicMismatchError unless value == magic
		end

		def write(type,value,options={})
			raise "magic value must be a string" unless value.is_a? String
			write_to_stream(value)
		end

	end

	# options:
	# - :length: the length of the array.
	#		when a symbol then the attribute identified vby this symbol will be read of the object to load.
	#		when nil then read the length from stream (see :length_field_type).
	# - :class: the class of each entry.
	#		when a class then instantiate the class and assign the values read from stream to the attributes of the instance.
	#		when nil then instantiate an OpenStruct and store the values in it.
	## - :length_field_type: when no array length is given, then the array length is read from the stream via a NumberSerializer.
	##		the type read from the stream can be set by this parameter. it is passed to the constructor of the NumberSerializer.
	class ArraySerializer < Serializer

		def subformat(name,&block)
			raise unless block
			DataFormat.new(name,&block) # FIXME pass items from current context to subformat?
		end

		def read(type,attribute_name,options={},&block)
			length = options[:length]
			item_clazz = options[:class] || OpenStruct

			# TODO validation

			array = []

			length.times do
				array << subformat(attribute_name,&block).read_from(context.stream, class: item_clazz)
			end

			set(attribute_name,array)
		end

		def write(type,attribute_name,options={},&block)
			array = get(attribute_name)

			# TODO validation

			array.each do |item|
				subformat(attribute_name,&block).write_to(stream)
			end
		end
	end

end # DataFormat