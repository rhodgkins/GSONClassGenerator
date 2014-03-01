require 'json'

module GSONClassGenerator

	public

	def self.generate(json_filename, class_name, output_directory, opts = {})
		
		begin
		json = JSON.parse(File.read(File.expand_path(json_filename)))
		rescue Exception => e
			abort "Invalid JSON: #{e.message}"
		end
		
		java_class = parse(json_filename, class_name)
		output_options = OutputOptions.new(opts)
		
		output(java_class, output_directory, output_options)
	end
	
	private
	
	GSON_SERIALIZED_NAME_IMPORT = "import com.google.gson.annotations.SerializedName;\n"
	
	def self.parse(json_filename, class_name)
		json = JSON.parse(File.read(File.expand_path(json_filename)))
		JavaClass.new(class_name, json)
	end
	
	def self.output(java_class, output_directory, opts)
		
		filename = File.join(File.expand_path(output_directory), "#{java_class.class_name}.java")
		
		File.open(filename, "w") do |file|
			
			file << GSON_SERIALIZED_NAME_IMPORT
			file << "\n"
			file << "\n"
			
			java_class.write(file, opts)
		end
		
		filename
	end
	
	class OutputOptions
		
		def initialize(opts)
			@getters = opts.fetch("getters".to_sym, false) === true
			@setters = opts.fetch("setters".to_sym, false) === true
			@final_fields = opts.fetch("final_fields".to_sym, false) === true
			@field_constructor = opts.fetch("field_constructor".to_sym, false) === true
			@boxed_primatives = opts.fetch("boxed_primatives".to_sym, false) === true
			
			# Can't have setters for final fields
			@setters = false if @final_fields
		end
		
		def getters?
			@getters
		end
		
		def setters?
			@setters
		end
		
		def final_fields?
			@final_fields
		end
		
		def field_constructor?
			@field_constructor
		end
		
		def boxed_primatives?
			@boxed_primatives
		end
	end
	
	class JavaClass
	
		public
		
		attr_reader :class_name, :fields
		
		def initialize(class_name, json, depth = 0)
			@class_name = class_name
			@nested_classes = Array.new
			@fields = Array.new
			@depth = depth
			
			if (json.is_a?(Array))
				
				# Pull out first object to examine what it looks like
				first_json = json.first
				fields = self.class.new(nil, first_json).fields
				
				@fields += fields
	
			else
			
				json.each do |k, v|
					field = JavaField.new(k, v)
					
					if (field.custom_class?)
						nested_name = self.class.get_nested_class_name(field)
						nested_class = self.class.new(nested_name, v, depth + 1)
						@nested_classes << nested_class
					end
					
					@fields << field
				end
				
			end
		end
		
		def write(stream, opts)
			tabs = self.class.indentation(@depth)
			field_tabs = self.class.indentation(@depth + 1)
			
			stream << "#{tabs}#{class_definition}\n"
			stream << "#{tabs}{\n"
			write_field_declarations(stream, field_tabs, opts)
			write_constructor(stream, field_tabs, opts)
			write_field_accessors(stream, field_tabs, opts)
			write_nested_classes(stream, opts)
			stream << "#{tabs}}\n"
		end
		
		private
		
		def self.get_nested_class_name(field)
			class_name = field.java_class
			if (field.is_array?)
				# Remove 's' if array
				class_name.chomp!("s")
			end
			class_name
		end
		
		def self.indentation(depth)
			Array.new(depth, "\t").join
		end
		
		def class_definition
			prefix = "public"
			if (@depth > 0)
				prefix += " static"
			end
			"#{prefix} final class #{@class_name}"
		end
		
		def write_field_declarations(stream, tabs, opts)
			@fields.each do |f|
				stream << "\n"
				f.write_declaration(stream, tabs, opts)
			end
		end
		
		def write_constructor(stream, tabs, opts)
				
			constructor_tabs = tabs + "\t"
				
			if (opts.field_constructor?)
				parameters = @fields.map { |f| "final #{f.type_definition(opts)} #{f.name}" }
				stream << "\n"
				stream << tabs
				stream << "public #{class_name}(#{parameters.join(', ')})\n"
				stream << tabs
				stream << "{\n"
				@fields.each do |f|
					f.write_constructor_assignment(stream, constructor_tabs, opts)
				end
				stream << tabs
				stream << "}\n"
			end
			if (opts.final_fields?)
			
				stream << "\n"
				stream << tabs
				stream << "public #{class_name}()\n"
				stream << tabs
				stream << "{\n"
				if (opts.field_constructor?)
					arguments = @fields.map { |f| f.default_initalized_object(opts) }
					# Call public constructor instead
					stream << constructor_tabs
					stream << "this(#{arguments.join(', ')});\n"
				else
					@fields.each do |f|
						f.write_default_constructor_assignment(stream, constructor_tabs, opts)
					end
				end
				stream << tabs
				stream << "}\n"
			end
		end
		
		def write_field_accessors(stream, tabs, opts)
			@fields.each do |f|
				f.write_accessors(stream, tabs, opts)
			end
		end
		
		def write_nested_classes(stream, opts)
			@nested_classes.each do |nested_class|
				stream << "\n"
				nested_class.write(stream, opts)
			end
		end
	end
	
	class JavaField
	
		private
		
		JAVA_TYPES = {
			FalseClass => "boolean",
			TrueClass => "boolean",
			Integer => "int", 
			Float => "float", 
			String => "String", 
			NilClass => "Object"
		}
		
		JAVA_TYPES_BOXED = { 
			"boolean" => "Boolean",
			"int" => "Integer", 
			"float" => "Float"
		}
		
		JAVA_DEFAULT_INITIALIZED_PRIMATIVES = {
			"boolean" => "false",
			"int" => "0", 
			"float" => "0.0f",
		}
		
		JAVA_KEYWORDS = ["public", "protected", "private", "abstract",  "final", "static", "strictfp", "transient", "volatile", "class", "enum", "interface", "extends", "implements", "void", "while", "do", "for", "if", "switch", "case", "default", "break", "continue", "return", "synchronized", "try", "catch", "throw", "throws", "finally", "super", "this", "new", "false", "true", "null", "instanceof", "package", "import", "assert", "boolean", "byte", "char", "short", "int", "long", "float", "double", "const", "goto"]
				
		public
		
		attr_reader :name, :java_class
		
		def initialize(key, value)
			@array_dimens = self.class.array_dimens(value)
			@json_key = key
			@name = self.class.javaify_key(key, self.is_array?)
			@java_class = self.class.class_for_value(key, value)
			@custom_class = !JAVA_TYPES.value?(@java_class)
		end
		
		def is_array?
			@array_dimens > 0
		end
		
		def custom_class?
			@custom_class
		end
		
		def write_declaration(stream, tabs, opts)
			stream << tabs
			stream << serialized_name_definition
			stream << tabs
			stream << field_definition(opts)
		end
		
		def write_default_constructor_assignment(stream, tabs, opts)
			stream << tabs
			stream << "#{@name} = #{default_initalized_object(opts)};\n"
		end
		
		def write_constructor_assignment(stream, tabs, opts)
			stream << tabs
			stream << "this.#{@name} = #{@name};\n"
		end
		
		def write_accessors(stream, tabs, opts)
			if (opts.getters?)
				write_getter_definition(stream, tabs)
			end
			if (opts.setters?)
				write_setter_definition(stream, tabs)
			end
		end
		
		def type_definition(opts)
			class_name = @java_class
			if (opts.boxed_primatives?)
				class_name = JAVA_TYPES_BOXED.fetch(class_name, @java_class)
			end
			array_def = Array.new(@array_dimens, "[]").join
			"#{class_name}#{array_def}"
		end
		
		def default_initalized_object(opts)
			if (opts.boxed_primatives?)
				"null"
			else
				JAVA_DEFAULT_INITIALIZED_PRIMATIVES.fetch(@java_class, "null")
			end
		end
		
		private
		
		def serialized_name_definition
			"@SerializedName(\"#{@json_key}\")\n"
		end
		
		def field_definition(opts)
			definition = "private"
			if (opts.final_fields?)
				definition += " final"
			end
			type_definition = type_definition(opts)
			"#{definition} #{type_definition} #{@name};\n"
		end
		
		def accessor_name
			@name.gsub(/^(.)/) { $1.upcase }
		end
		
		def write_getter_definition(stream, tabs)
			stream << "\n"
			stream << tabs
			stream << "public final #{@type_definition} get#{accessor_name}()\n"
			stream << tabs
			stream << "{\n"
			stream << tabs
			stream << "\treturn #{@name};\n"
			stream << tabs
			stream << "}\n"
		end
		
		def write_setter_definition(stream, tabs)
			stream << "\n"
			stream << tabs
			stream << "public final void set#{accessor_name}(final #{@type_definition} #{@name})\n"
			stream << tabs
			stream << "{\n"
			stream << tabs
			stream << "\tthis.#{@name} = #{@name};\n"
			stream << tabs
			stream << "}\n"
		end
		
		# STATIC METHODS
		
		def self.array_dimens(value)
			
			dimens = 0
			
			array = value
			while (array.is_a?(Array))
				dimens += 1
				array = array.first
			end
			
			dimens
		end
		
		def self.class_for_value(key, value)
		
			java_class = nil
			
			if (value.is_a?(Hash))
				# Use key as class name
				java_class = key
							
				# Clean up first character
				java_class = java_class.gsub(/^[^\p{Pc}\p{Alpha}\p{Sc}]/, "")
		
				# Clean up allowed characters
				java_class = java_class.gsub(/[^\p{Pc}\p{Alnum}\p{Sc}]/, "")
				
				# Upper case it
				java_class = java_class.gsub(/^([\p{Pc}\p{Sc}]*)(\p{Alpha})/) { "#{$1}#{$2.upcase}" }
				
			elsif (value.is_a?(Array))
			
				# First check that the array is a native one
				first_object = value.first
			
				java_class = self.class_for_value(key, first_object)
			else
			
				JAVA_TYPES.each do |ruby_cls, java_cls|
					if (value.is_a?(ruby_cls))
						java_class = java_cls
						break
					end
				end
			end
			
			abort "No class is able to be determined for JSON key #{key} (ruby class: #{value.class})" if !java_class
			
			java_class
		end
		
		def self.javaify_key(json_key, is_array)
			field_name = json_key
			
			if (is_array)
				if (!field_name.end_with?("s"))
					# Append 's' if it doesn't have it
					field_name += "s"
				end
			end
			
			# Clean up first character
			field_name = field_name.gsub(/^[^\p{Pc}\p{Alnum}\p{Sc}]+/, "")
	
			# Clean up allowed characters
			field_name = field_name.gsub(/[^\p{Pc}\p{Alnum}\p{Sc}]/, "_")
			
			# Camel case underscores
			field_name = field_name.gsub(/(?!^_)_+(.)/) { $1.upcase }
			
			# Clean up field name in case its a Java keyword
			if (!(JAVA_KEYWORDS.index(field_name) === nil))
				field_name += "_"
			end
			
			# Lower case first letter, but allow if 2 or more upper case characters are present
			field_name = field_name.gsub(/^(\p{Upper})(?!\p{Upper}+)/) { $1.downcase }
			
			field_name
		end
	end
end
