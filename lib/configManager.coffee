util			= require 'util'
yaml			= require 'libyaml'

exports.manage = (o) ->
	argv = process.argv
	try 
		[config] = yaml.readFileSync(o.path)
	catch err
		util.log "Creating new config"
		config = {}
		config = o.defaults if o.defaults
		yaml.writeFileSync(o.path, config)
	
	if argv[2] is 'config'
		if argv.length is 3
			console.log util.inspect config
			process.exit 1
			
		else unless argv.length is 5
			console.log 'Incorrect params'
			process.exit 1
			
		key = argv[3]
		val = argv[4]
		keyPaths = key.split '.'
		temp = config
		
		for keyPath, i in keyPaths
			temp[keyPath]?= {}
			
			if i + 1 is keyPaths.length
				temp[keyPath] = val
			else 
				temp = temp[keyPath]

		yaml.writeFileSync(o.path, config)
			
		process.exit 1

	for r in o.required 
		parts = r.split '.'
		tmp = config
		for part in parts
			unless tmp[part]
				console.log "Missing config key #{r}"
				process.exit 1
				 
			tmp = tmp[part] 
	
	
	return config
	