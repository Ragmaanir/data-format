require 'ostruct'

require 'binary_size'
require 'serializers'

# TODO groups: group(:header) do ... end

# 
module DataFormat

	def self.description(name=nil,&block)
		#Builder.new(name,&block).data_format
		DataFormat.new(name,&block)
	end

	class DataFormat
		attr_accessor :name, :object, :block

		def initialize(name=nil,&block)
			self.block = block
			self.name = name
		end

		def read_from(stream,options={})
			self.object = options[:object] || (options[:class] || OpenStruct).new
			dsl = SerializationContext.new(:read,object,stream)
			dsl.instance_eval(&block)
			object
		end
	end

	# The SerializationContext encapsulates:
	#		- the object that loaded values are read/written to
	#		- the stream
	#		- the used DSL: {keyword => serializer class}
	#		- the mode (:read,:write)
	#		- the byte order (:big_endian,:little_endian)
	# The ruby blocks that are used to specify the data-format
	# are executed in this context (instance_eval).
	#
	# For each keyword in the DSL a method is generated that instantiates and executes
	# the mapped serializer.
	#
	# Method missing delegates all calls to the stored object so that
	# attributes of the object (which can be set to a value read from the stream)
	# can be used in switches, if conditions and method calls.
	class SerializationContext
		DefaultDSL = {
				int: IntegerSerializer,
				float: FloatSerializer,
				string: StringSerializer,
				magic: MagicSerializer,
				array: ArraySerializer
			}

		attr_accessor :object, :stream, :mode, :dsl, :byte_order

		def initialize(mode,object,stream,options={})
			options = { dsl: DefaultDSL, byte_order: :big_endian }.merge(options)
			self.object = object
			self.stream = stream
			self.mode = mode
			self.dsl = options[:dsl]
			self.byte_order = options[:byte_order]
		end

		def big_endian?
			byte_order == :big_endian
		end

		def little_endian?
			byte_order == :little_endian
		end

		def instantiate_serializer(name)
			s = @dsl[name] || raise("Serializer not found: #{name}")
			s.new(self)
		end

		def dsl=(dsl)
			@dsl = dsl
			@dsl.each do |k,v|
				# TODO raise when local variable named like a type
				self.instance_eval <<-CODE,__FILE__,__LINE__
					def #{k}(*args,&block)
						serializer = instantiate_serializer(:#{k})
						serializer.#{mode}(:#{k},*args,&block)
					end
				CODE
			end
		end

		def method_missing(meth,*args)
			object.send(meth,*args)
		end
	end

end
