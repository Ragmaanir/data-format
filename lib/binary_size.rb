class BinarySize

	Units = [:bits,:bytes,:kb,:mb,:gb,:tb]

	attr_reader :unit

	def initialize(value,unit)
		raise "invalid unit: #{unit}" unless Units.include? unit
		raise "value #{value} is no integer" unless value.is_a? Integer
		@value = value
		@unit = unit
	end

	Units.each do |u|
		class_eval <<-CODE
			def #{u}?
				self.unit == :#{u}
			end
		CODE
	end

	def bits
		if not bits?
			BinarySize.new(self.to_i)
		else
			dup
		end
	end

	def to_s
		"#{@value} #{unit}"
	end
	
	def to_i
		if bits?
			@value
		else
			#@value * 8 * (1024**(Units.index(unit)-1))
			@value * unit_factor
		end
	end

	Units.each do |u|
		class_eval <<-CODE
			def to_#{u}
				to_i/BinarySize.unit_factor(:#{u}).to_f
			end
		CODE
	end

	def ==(other)
		raise "other is no binary size (#{other.class})" unless other.kind_of? BinarySize
		to_i == other.to_i
	end

	def +(other)
		raise "you can only add sizes but other was: #{other.class}" unless other.kind_of?(BinarySize)
		BinarySize.new(to_i+other.to_i,:bits)
	end

	def unit_factor
		BinarySize.unit_factor(@unit)
	end

	def self.unit_factor(unit)
		case(unit)
		when :bits then 1
		when :bytes then 8
		else
			8 * (1024**(Units.index(unit)-1))
		end
	end

end

class Integer
	BinarySize::Units.each do |u|
		class_eval <<-CODE
			def #{u}
				BinarySize.new(self,:#{u})
			end
		CODE
	end
end