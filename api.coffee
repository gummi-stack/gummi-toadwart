express = require 'express'
util = require 'util'
fs = require 'fs'
http = require 'http'
{spawn, exec} = require('child_process')
net = require 'net'
procfile = require 'procfile'

redis = require('redis-url').connect()
mongoFactory = require 'mongo-connection-factory'

mongoUrl = "mongodb://10.1.69.105/gummi"
ObjectID = require('mongodb').ObjectID

async = require 'async'
colors = require 'colors'

###

TODO

do nastartovanych aplikaci pridat info na kterem nodu bezi



###

class Igthorn
	start: (data, done) ->
		util.log "Volam start: #{data.slug}, #{data.cmd} #{data.name} #{data.worker}"
		data.env = {GUMMI: 'BEAR'}
		
		@request '10.1.69.105', 81, '/ps/start', data, (res) ->
			done res
			
	
	softKill: (data, done) ->
		@request '10.1.69.105', 81, '/ps/kill', data, (res) ->
			done res
		
		
	request: (ip, port, url, data, done) ->
		data = JSON.stringify data
		opts = 
			host: ip
			port: 81
			path: url
			method: 'POST'
			headers:
				'Content-Type': 'application/json; charset=utf-8'
				'Content-Length': data.length
		
		req = http.request opts, (res) =>
			res.setEncoding 'utf8' 
			
			buffer = ''
			res.on 'data', (chunk) ->
				buffer += chunk
			res.on 'end', () ->
				util.log "----- " + buffer
				done JSON.parse buffer
				
		req.write data
		req.end()

igthorn = new Igthorn
# 
# igthorn.start '/shared/slugs/testing.git-master-fa6da3f8eb256f5964a522f55a7d1f356d7ce6b7.tgz', 'node web.js', ->

# return
class NginxConfig
	writeConfig: (name, config) ->
		fs.writeFileSync "/nginx/#{name}.conf", config
	
	reload: (done) ->
		exec 'ssh -i /root/.ssh/id_rsa 10.1.69.100 -C /etc/init.d/nginx reload', (err, stdout, stderr) ->
			done arguments


	
nginx = new NginxConfig

app = express()

app.post '/', (req, res)->
	buffer = ''
	req.on 'data', (data) ->
		buffer += data
	req.on 'end', () ->


app.get '/reloadrouter', (req, res) ->
	nginx.reload (o) ->
		res.json o


app.get '/apps/:app/:branch/logs', (req, res) ->
	app = req.params.app
	app = app + '.git' unless app.match /\.git/
	branch = req.params.branch 
	tail = req.query.tail
	start = new Date().getTime() * 1000;
	util.log util.inspect tail


	processResponse = (response) ->
		#todo colorizovat podle 
		for time,i in response by 2
			data = response[i+1]
			date = new Date(time/1000)
			line = date.toJSON().replace(/T/, ' ').replace(/Z/, ' ').cyan
			matches = data.match /([^\s]*)\s- -(.*)/
			worker = matches[1]
			if worker is 'dyno'
				worker = worker.magenta
			else
				worker = worker.yellow
			
			line += "[#{worker}] #{matches[2]}\n"
			res.write line
			# process.stdout.write line

	
	closed = no
	res.on 'close', ->
		closed = yes

	getNext = () ->
		return if closed 
		
		# nacteni novych od posledniho dotazu
		opts = ["#{app}/#{branch}", '+inf', start, 'WITHSCORES']
		start = new Date().getTime() * 1000;

		redis.zrevrangebyscore opts, (err, response) ->
			# util.log 'dalsi ' + start
			# util.log util.inspect res.complete
			
			processResponse response.reverse()
			setTimeout (() -> getNext()), 1000 
		


	opts = ["#{app}/#{branch}", start, '-inf', 'WITHSCORES', 'LIMIT', '0', '10']
	# nacteni odted do historie
	redis.zrevrangebyscore opts, (err, response) ->
		processResponse response.reverse()
		if tail
			getNext()
		else 
			res.end()
			
		# TODO zavre se pri ukonceni requestu ?
app.get '/apps/:app/:branch/ps', (req, res) ->
	app = req.params.app
	app = app + '.git' unless app.match /\.git/
	branch = req.params.branch 
	mongoFactory.db mongoUrl, (err, db) ->
	
		db.collection 'instances', (err, instances) ->
			q = 
				app: app
				branch: branch
			instances.find(q).toArray (err, results) ->
				res.json results
	
	


app.get '/apps/:app/:branch/ps/stop', (req, res) ->
	app = req.params.app
	app = app + '.git' unless app.match /\.git/
	branch = req.params.branch 

	mongoFactory.db mongoUrl, (err, db) ->
	
		db.collection 'instances', (err, instances) ->
			q = 
				app: app
				branch: branch
			util.log 'xxx'
			instances.find(q).toArray (err, results) ->
				res.json 
					status: 'ok'
					message: 'Asi sem je zabil, ale nekontroloval jsem to'


				for result in results
					o = 	
						name: result.dynoData.name
						pid: result.dynoData.pid
					do(result) ->
						igthorn.softKill o, (res) ->
							
							if res.status is 'ok'
								console.log 'mazu'
								q = _id: result._id
								util.log util.inspect q
								instances.remove q, () ->
									util.log util.inspect arguments
							util.log util.inspect res

	
	


app.get '/apps/:app/:branch/ps/restart', (req, res) ->
	app = req.params.app
	app = app + '.git' unless app.match /\.git/
	branch = req.params.branch 
	
	## najit zaznam v mongu
	mongoFactory.db mongoUrl, (err, db) ->

		db.collection 'builds', (err, collection) ->
			q = 
				app: app
				branch: branch
			util.log q
			
			collection.find(q).sort(timestamp: -1).limit(1).toArray (err, results) ->
				[build] = results
				
				
				processes = []
				results = []
				## nastartovat nove procesy podle skalovaci tabulky a procfile
				
				for proc, data of build.procfile
					cmd = data.command
					cmd += " " + data.options.join ' ' if data.options
					## todo brat v potaz skalovani a pridelovani spravneho cisla
					## TODO pouze test
					for i in [1..2]
						processes.push {name: "#{proc}-#{i}", type: proc , cmd: cmd}

				async.forEach processes, ((item, done)->
					opts = 
						slug: build.slug
						cmd: item.cmd
						name: "#{app}/#{branch}"
						worker: item.name
						logName: "#{app}/#{branch}"
						logApp: item.name
						
					igthorn.start opts, (r) ->
						
						util.log util.inspect r
						item.result = r
						done()
						util.log util.inspect build
						
						db.collection 'instances', (err, instances) ->
							o = 
								dynoData: r
								buildId: build._id
								app: app
								branch: branch
								opts: opts 
								time: new Date
								
							instances.insert o
							
						
						
						
				), (err) ->
					build.out = processes 
					console.log "#{app} started"
					## TODO ocheckovat jestli vsechno bezi
					## prepnout router
					servers = "\n"
					for state in processes
						ip = state.result.ip
						port = 5000
						servers += "\tserver #{ip}:#{port};\n"
					
					upstream = "#{branch}.#{app}".replace /\./g, ''
					cfg = """					
						upstream #{upstream} {
						   #{servers}
						}

						server {

						  listen 80;
						  server_name #{branch}.#{app}.nibbler.cz;
						  location / {
						    proxy_pass http://#{upstream};
						  }
						}
					"""
					nginx.writeConfig upstream, cfg
					nginx.reload (o) ->
						build.conf = cfg
						build.nginx = o
						res.json build
					
						
					## soft kill starejch
					## pockat jestli se neukonci
					## kill -9 starejch
					
					
					
				# util.log util.inspect processes
					
				# igthorn.start ''
				

	
	# res.json
	# 	app: req.params.app


app.get '/ps/start', (req, res) ->
	lxc = new Lxc

	lxc.on 'data', (data) ->
		util.log data

	lxc.on 'error', (data) ->
		util.log 'ERR: ' + data

	lxc.on 'exit', (code) ->
		util.log 'EXIT: ' + code

	lxc.setup dhcp.get(), (name) ->
		approot = "#{lxc.root}app"
		fs.mkdirSync approot

		file = req.query.slug
		env = JSON.parse req.query.env
		cmd = req.query.cmd
		console.log "tar -C #{approot}/ -xzf #{file}"
		for key, val of env
		    util.log key, val
		    process.env[key] = val	

		process.env.FFF='joooooo'
		exec "tar -C #{approot}/ -xzf #{file}", (error, stdout, stderr) ->
			lxc.exec '/buildpacks/startup /app run ' + cmd, (exitCode) ->
				lxc.dispose () ->
			res.json
				pid: lxc.process.pid
				ip: dhcp.ip.join '.'
				name: lxc.name
# 
# app.get '/ps/kill', (req, res) ->
# 	process.kill(req.query.pid * -1)
# 	lxc = new Lxc req.query.name
# 	lxc.dispose () ->
# 		res.end 'je po nem Jime'
# 
# 
# app.get '/ps/status', (req, res) ->
# 	exec "ps #{req.query.pid}", (error, stdout, stderr) ->
# 		res.end stdout
# 
# app.get '/ps/statusall', (req, res) ->
# 	exec "ps afx", (error, stdout, stderr) ->
# 		res.end stdout
# 
# 
# 
# 
# app.get '/git/:repo/:branch/:rev', (req, res) ->
# 	p = req.params
# 	fileName = "#{p.repo}-#{p.branch}-#{p.rev}"
# 	file = "/shared/git-archive/#{fileName}.tar.gz"
# 	slug = "/shared/slugs/#{fileName}.tgz"
# 	process.env.TERM = 'xterm'
# 	
# 	req.on 'end', () ->
# 		lxc = new Lxc
# 
# 		lxc.on 'data', (data) ->
# 			res.write data
# 
# 		lxc.on 'error', (data) ->
# 			res.write data
# 
# 
# 		lxc.setup dhcp.get(), (name)->
# 			util.log "lxc name #{name}"
# 			#res.write "lxc name #{name}\n"
# 
# 			util.log
# 			approot = "#{lxc.root}app"
# 			fs.mkdirSync approot
# 
# 			util.log "tar -C #{approot} -xvzf #{file}"
# 			#res.write util.inspect process.env
# 			exec "tar -C #{approot}/ -xzf #{file}", (error, stdout, stderr) ->
# 				files = fs.readdirSync approot
# 				util.log util.inspect files
# 
# 				try
# 					procData = fs.readFileSync("#{approot}/Procfile").toString()
# 					procData = procfile.parse procData
# 
# 				catch e
# 					res.write "ERR: Missing procfile\n"
# 					return exit 1
# 
# 
# 				buildData =
# 					app: p.repo
# 					branch: p.branch
# 					rev: p.rev
# 					timestamp: new Date
# 					slug: slug
# 					procfile: procData
# 
# 				lxc.exec '/buildpacks/startup /app', (exitCode) ->
# 					exec "tar -Pczf #{slug} -C #{approot} .", (error, stdout, stderr) ->
# 						mongoFactory.db mongoUrl, (err, db) ->
# 							db.collection 'builds', (err, collection) ->
# 								collection.insert buildData
# 
# 						exit exitCode
# 
# 		exit = (exitCode) ->
# 			lxc.dispose ->
# 				res.end("94ed473f82c3d1791899c7a732fc8fd0_exit_#{exitCode}\n")
# 

app.listen 80
util.log 'server listening on 80'

