express 		= require 'express'
util			= require 'util'
fs				= require 'fs'
{spawn, exec}	= require 'child_process'
net 			= require 'net'
procfile		= require 'procfile'

config			= require './config'
Dhcp			= require './lib/dhcp.coffee'
Lxc 			= require './lib/lxc'
PsManager		= require './lib/psmanager'

require 'coffee-trace'
fn = util.inspect
util.inspect = (a,b,c) -> fn a,b,c,yes


psmanager = new PsManager config




dhcp = new Dhcp config.dhcp 
mongoFactory = require 'mongo-connection-factory'

mongoUrl = "mongodb://localhost/gummi"

app = express()
app.use express.bodyParser()

expressSwaggerDoc = require 'express-swagger-doc'
app.use expressSwaggerDoc(__filename, '/docs')
app.use app.router
app.use express.errorHandler()

app.get '/', (req, res) ->
	res.json 
		name: config.name
		id:	config.id
		containersCount: psmanager.getCount()
		motd: 'You bitch'
			

###
Start process from slug in new container

:file - slug path
:cmd - command to run
:rendezvous - start in rendezvous mode
:logApp - application name for loogging
:logName - log name  

###
app.post '/ps/start', (req, res) ->
	file = req.body.slug
	cmd = req.body.cmd
	env = req.body.env
	rendezvous = req.body.rendezvous
	logApp = req.body.logApp
	logName = req.body.logName

	return res.json error: 'Missing slug' unless file

	lxc = new Lxc

	lxc.on 'data', (data) ->
		util.print "dada " + data

	lxc.on 'error', (data) ->
		util.print 'ERR: ' + data

	lxc.on 'exit', (code) ->
		util.print 'EXIT: ' + code

	lease = dhcp.get()
	lxc.setup lease, (name) ->
		approot = "#{lxc.root}app"
		fs.mkdirSync approot

		# file = req.query.slug
		# env = JSON.parse req.query.env
		# cmd = req.query.cmd
		# console.log "tar -C #{approot}/ -xzf #{file}"
		# for key, val of env
		# 		    util.log key, val
		# 		    process.env[key] = val
		
		env.LOG_CHANNEL = logName
		env.LOG_APP = logApp
		env.LOG_CMD = cmd
		env.GUMMI_ID = config.id
		
		exec "tar -C #{approot}/ -xzf #{file}", (error, stdout, stderr) ->
			
			port = 5000
			env.PORT = port
			if rendezvous
				lxc.rendezvous '/buildpacks/startup /app run ' + cmd, env, (data) ->
					# console.log "::#{port}"
					
					pso = psmanager.add data.pid, lxc.name, lease.ip, data.port
					pso.rendezvousURI = "tcp://10.1.69.105:#{data.port}"
					res.json pso
						
						
			else
				lxc.exec '/buildpacks/startup /app run ' + cmd, env, (exitCode) ->
					lxc.dispose () ->
						
				pso = psmanager.add lxc.process.pid, name, lease.ip, port
				res.json pso

	
	

###
Kill process by pid
###
app.post '/ps/kill', (req, res) ->
	util.log util.inspect req.body

	try 
		throw new Error 'Invalid pid' unless req.body.pid
		process.kill(req.body.pid * -1)
	catch err
		util.log "#{req.body.name} #{req.body.pid} uz byl asi mrtvej" 

	psmanager.remove req.body.pid
	
	lxc = new Lxc req.body.name
	# util.log 'disposuju'
	lxc.dispose () ->
		# util.log 'disposujuxxx'
		res.json 
			status: 'ok'
			message: 'Process successfully killed'

	
## TEST
app.get '/ps/status', (req, res) ->
	res.json psmanager.pids
	# exec "ps #{req.query.pid}", (error, stdout, stderr) ->
	# 	res.end stdout

## TEST
app.get '/ps/statusall', (req, res) ->
	exec "ps afx", (error, stdout, stderr) ->
		res.end stdout



## TODO na master

app.get '/git/:repo/:branch/:rev', (req, res) ->
	p = req.params
	fileName = "#{p.repo}-#{p.branch}-#{p.rev}"
	file = "/shared/git-archive/#{fileName}.tar.gz"
	slug = "/shared/slugs/#{fileName}.tgz"
	process.env.TERM = 'xterm'

	req.on 'end', () ->
		lxc = new Lxc

		lxc.on 'data', (data) ->
			res.write data

		lxc.on 'error', (data) ->
			res.write data


		lxc.setup dhcp.get(), (name)->
			util.log "lxc name #{name}"
			res.write "lxc name #{name}\n"

			util.log
			approot = "#{lxc.root}app"
			fs.mkdirSync approot

			util.log "tar -C #{approot} -xvzf #{file}"
			res.write "rozbaluju \n"			
			exec "tar -C #{approot}/ -xzf #{file}", (error, stdout, stderr) ->
				res.write "rozbaleno 	\n"			
				files = fs.readdirSync approot
				util.log util.inspect files

				try
					procData = fs.readFileSync("#{approot}/Procfile").toString()
					procData = procfile.parse procData

				catch e
					res.write "ERR: Missing procfile\n"
					return exit 1


				buildData =
					app: p.repo
					branch: p.branch
					rev: p.rev
					timestamp: new Date
					slug: slug
					procfile: procData

				env = {}
				env.LOG_CHANNEL = 'TODOkanalek'
				env.LOG_APP = 'TODOappka'
				res.write "excuju  \n"
				lxc.exec '/buildpacks/startup /app', env, (exitCode) ->
					exec "tar -Pczf #{slug} -C #{approot} .", (error, stdout, stderr) ->
						mongoFactory.db mongoUrl, (err, db) ->
							db.collection 'builds', (err, collection) ->
								collection.insert buildData

						exit exitCode

		exit = (exitCode) ->
			lxc.dispose ->
				res.end("94ed473f82c3d1791899c7a732fc8fd0_exit_#{exitCode}\n")



app.listen config.port
util.log "Toadwart \"#{config.name}\" serving on #{config.port}"

