GSONClassGenerator
==================

Ruby script generating JSON model objects in Java when using GSON

Usage:

    ruby GSONClassGenerator.rb [-gfscb] json_file class_name [output_directory]

Flags:

**g** - Generate getters.

**s** - Generate setters.

**f** - All fields are final, this will also generate a public no arguement
constructor for all classes and the 's' flag is ignored.

**c** - A public constructor is generated for all the classes with all the
fields as arguments. 	b - All primative types are boxed.

Arguments:

**json_file** - The file you want to generate the model class from.

**class_name** - The top level class name, and therefore the name of the output
file.

**output_directory** - The location to save the generated model class. If this
is not provided the current directory will be used.
