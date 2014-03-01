require 'date'

Gem::Specification.new do |s|
  s.name        			= 'gson-class-generator'
  s.version     			= '1.0.1'  
  s.date 				= Date.today
  s.summary     			= 'Ruby script generating JSON model objects in Java when using GSON'
  s.authors     			= ["Rich Hodgkins"]
  s.email       			= 'github@rhodgkins.co.uk'
  s.files       			= Dir['lib/**/*.rb']
  s.executables			    	= 'gson-class-generator'
  s.add_runtime_dependency	  	'json'
  s.homepage    			= 'https://github.com/rhodgkins/GSONClassGenerator'
  s.license     			= 'MIT'
end
