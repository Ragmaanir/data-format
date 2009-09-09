require File.join(File.dirname(__FILE__),'data_format')

# 
module Serializable
	def self.included(cls)
		cls.extend(ClassMethods)
	end

	module ClassMethods
		attr_accessor :data_formats
		attr_accessor :default_data_format_name

		def data_format(name,&block)
			self.data_formats ||= {}
			self.data_formats.merge!(name => DataFormat.description(name,&block))
		end

		def default_data_format
			data_formats[default_data_format_name]
		end

		def load_from(stream,data_format=nil)
			df = data_formats[data_format] || default_data_format
			df.read_from(stream,:object => self.new)
		end
	end

	def load_from(stream)
		raise NotImplementedError # TODO implemented
	end

	def save_to(stream)
		raise NotImplementedError # TODO implemented
	end
end
