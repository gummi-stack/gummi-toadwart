express = require 'express'
util = require 'util'
fs = require 'fs'
{spawn, exec} = require('child_process')
net = require 'net'
procfile = require 'procfile'

redis = require('redis-url').connect()
#mongodb = require 'mongodb'

mongoFactory = require 'mongo-connection-factory'

mongoUrl = "mongodb://localhost/gummi"

Lxc = require './lib/lxc'

#server = null
#col
#server = new mongodb.Server "localhost", 27017, {}
#new mongodb.Db('gummi', server, {}).open (err, client) ->
#	throw err if err
#	collection = new mongodb.Collection client, 'builds'


# lxc.setup (name)->
# 	util.log "lxc name #{name}" 
# 	lxc.exec 'uptime -h', ->
# 		util.log "command end" 
# 
# 		lxc.dispose ->
# 			util.log "lxc name #{name} - disposed" 
# 	


app = express()
#app.use express.bodyParser()

app.post '/', (req, res)->
	
	buffer = ''
	req.on 'data', (data) ->
		buffer += data
	req.on 'end', () ->
		lxc = new Lxc
		
		data = JSON.parse buffer
		command = data.command
		return unless command
		util.log 'Starting rendezvous: ' + command
	

		lxc.setup (name)->
			util.log "lxc name #{name}" 
			port = lxc.rendezvous command, ->
				util.log "command end" 

				lxc.dispose ->
					util.log "lxc name #{name} - disposed" 
			res.send rendezvousURI: "tcp://10.1.69.105:#{port}"


app.get '/apps/:app/:branch/restart', (req, res) ->
	p = req.params
	mongoFactory.db mongoUrl, (err, db) ->
		db.collection 'builds', (err, collection) ->
			q =
				app: p.app
				branch: p.branch
			collection.find(q).sort(timestamp: -1).limit(1).toArray (err, results) ->
				result = results[0]

				lxc = new Lxc

				lxc.on 'data', (data) ->
					util.log data

				lxc.on 'error', (data) ->
					util.log 'ERR: ' + data

				lxc.on 'exit', (code) ->
					util.log 'EXIT: ' + code


				lxc.setup (name)->
					approot = "#{lxc.root}app"
					fs.mkdirSync approot
					file = result.slug
					
					exec "tar -C #{approot}/ -xzf #{file}", (error, stdout, stderr) ->

						files = fs.readdirSync approot
						util.log util.inspect files

						command = '/buildpacks/startup /app run ' + result.procfile.web.command + ' ' + result.procfile.web.options.join ' '
						res.end()
						lxc.exec command, ( exitCode ) ->
							lxc.dispose () ->



app.get '/git/:repo/:branch/:rev', (req, res) ->
	p = req.params
	fileName = "#{p.repo}-#{p.branch}-#{p.rev}"
	file = "/shared/git-archive/#{fileName}.tar.gz"
	slug = "/shared/slugs/#{fileName}.tgz"

	req.on 'end', () ->
		lxc = new Lxc

		lxc.on 'data', (data) ->
			res.write data

		lxc.on 'error', (data) ->
			res.write data


		lxc.setup (name)->
			util.log "lxc name #{name}"
			res.write "lxc name #{name}\n"
			
			util.log
			approot = "#{lxc.root}app"
			fs.mkdirSync approot
			
			util.log  "tar -C #{approot} -xvzf #{file}"
			
			exec "tar -C #{approot}/ -xzf #{file}", (error, stdout, stderr) ->

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

				lxc.exec '/buildpacks/startup /app', ( exitCode ) ->

					exec "tar -Pczf #{slug} -C #{approot} .", (error, stdout, stderr) ->
						mongoFactory.db mongoUrl, (err, db) ->
							db.collection 'builds', (err, collection) ->
								collection.insert buildData

						exit exitCode

		exit = ( exitCode ) ->
			lxc.dispose ->
				res.end( "94ed473f82c3d1791899c7a732fc8fd0_exit_#{exitCode}\n" )




	
app.listen 80
util.log 'server listening on 80'


# 
# lxc.setup (name)->
# 	util.log "lxc name #{name}" 
# 
# 	server = net.createServer (socket) ->
# 		term = pty.spawn 'bash', [], {
# 			name: 'xterm-color',
# 			cols: 80,
# 			rows: 30,
# #			cwd: process.env.HOME,
# #			env: process.env
# 		}
# 		
# 		term.on 'data', (data) ->
# 			socket.write data
# 		term.on 'exit', ->
# 			socket.end()
# 
# 		socket.on 'data', (data) ->
# 			term.write data
# 		
# 		socket.on 'end', ->
# 			term.kill 'SIGKILL'
# 			term.end()
# 			util.log 'client disconnected'
# 		
# 	server.listen 5000
# 	# lxc.exec 'uptime -h', ->
# 	# 	util.log "command end" 
# 
# 	lxc.dispose ->
# 		util.log "lxc name #{name} - disposed" 
# 
# 

return

processFile = "#{__dirname}/processes.json" 
processes = {}			

loadProcesses = ->
	x = fs.readFileSync processFile
	processes = JSON.parse x
	
loadProcesses()	
#util.log util.inprocesses 

saveProcesses = ->
	fs.writeFileSync processFile, JSON.stringify processes 
	util.log util.inspect processes





app = express.createServer()


app.get '/', (req, res)->
	res.header 'Access-Control-Allow-Origin', '*'
	res.send processes

app.get '/kill/:id', (req, res)->
	#req.params.id
#    process.exit()

	p = processes[req.params.id]
	return unless p
	
	delete processes[req.params.id]
	saveProcesses()
	
	x = process.kill(-p.pid,'SIGHUP')
	util.log util.inspect x
	res.send 'zabito': "x"
	
	
app.get '/start/:slug', (req, res)->
	res.send('user ' + req.params.slug)

    
#    spawn 'php www/index.php ' + presenter

	actions = ['/home/bender/start-ephemeral','run', req.params.slug]
	p = spawn 'setsid', actions
	#util.log util.inspect p
	
	processes[p.pid] = {
		pid: p.pid
		slug: req.params.slug
	}
	saveProcesses()
	
	pi = processes[p.pid]
	
	pi.stdout = ''
	pi.stderr = ''
	
	res.send('user ' + req.params.slug + "pid:   " + p.pid)
	p.stdout.on 'data', (data) ->
		util.log '' + data
		pi.stdout += data


	p.stderr.on 'data', (data) ->
		util.log 'stderr: ' + data
		pi.stderr += data
		
	p.on 'exit', (code) ->
		util.log 'child process exited with code ' + code
    

app.listen 80
util.log 'server listening on 80 --'
