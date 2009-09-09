# 
class StringStream
	attr_accessor :position
	attr_accessor :string

	def initialize(str="")
		@string = str
		@position = 0
	end

	def read(n)
		value = @string[@position...(@position+n)]
		@position += n
		value
	end

	def readbytes(n)
		str = read(n)

		raise EOFError if str == nil
		raise "data truncated" if str.size < n

		str
	end

	def readline(sep)
		str = @string[@position...@string.length][/.*?#{sep}/]
		@position += str.length
		str
	end

	def write(data)
		@string << data
	end

	def self.create(*args)
		stream = StringStream.new

		args.each do |arg|
			if arg.is_a? String
				stream.write([arg].pack("a*"))
			elsif arg.is_a? Integer
				if arg.size == 4
					stream.write([arg].pack("i").reverse!)
				else
					stream.write([arg].pack("l").reverse!)
				end
			elsif arg.is_a? Float
				stream.write([arg].pack("g"))
			else "unknown argument"
				raise
			end
		end

		stream
	end
end