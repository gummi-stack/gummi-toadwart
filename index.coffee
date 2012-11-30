express 		= require 'express'
util			= require 'util'
fs				= require 'fs'
{spawn, exec}	= require 'child_process'
net 			= require 'net'
procfile		= require 'procfile'
request			= require 'request'
filesize		= require 'filesize'
uuid			= require 'node-uuid'
# config			= require './config'
Dhcp			= require './lib/dhcp.coffee'
Lxc 			= require './lib/lxc'
PsManager		= require './lib/psmanager'

storage			= require './lib/storage/'
iptables		= require './lib/iptables'
require 'coffee-trace'
fn = util.inspect
util.inspect = (a,b,c) -> fn a,b,c,yes

config = {}

bootstrap = (done) ->
	
	configManager = require './lib/configManager'

	config = configManager.manage
		path: '/etc/toadwart.yaml'
		required: ['name', 'ip', 'port', 'id', 'lxc.iface', 'lxc.address', 'lxc.userResolv', 'wan.iface']
		defaults:
			id: uuid.v4()
			lxc:
				userResolv: yes

	
	done()
		

	
	
bootstrap () ->	

	psmanager = new PsManager config

	psmanager.on 'remove', (info) ->
		util.log "Cleaning lxc #{info.name}"
		lxc = new Lxc info.name
		lxc.dispose()


	psmanager.run()

	
	nm = require('netmask')
	Netmask = require('netmask').Netmask
	net = new Netmask config.lxc.address


	basePort = 5000
	rules = []
	portMap = []
	for i in [1...net.size-2]
		basePort++
		nip = nm.long2ip(nm.ip2long(net.first) + i)
		portMap[nip] = 
			 publicIp: config.ip
			 publicPort: basePort
			 privatePort: 5000
			 privateIp: nip
		rules.push "#{basePort}:#{nip}:5000"
	
	rules = rules.join "\n"
	
	env = 
		RULES: rules
		WAN_IFACE: config.wan.iface
		LXC_IFACE: config.lxc.iface
		LXC_IP: net.first
		LXC_MASK: net.mask
		
			
	exec "#{__dirname}/iptables.sh", env: env, (err, stdout, stderr) ->
		console.log err if err
		console.log stdout if stdout
		console.log stderr if stderr

		dhcpConfig = 
			addresses: nm.long2ip(nm.ip2long(net.first) + 1) + "-" + net.last
			mask: net.mask
			route: net.first
			portMap: portMap
			

		dhcp = new Dhcp dhcpConfig 

		app = express()
		app.use express.bodyParser()

		expressSwaggerDoc = require 'express-swagger-doc'
		app.use expressSwaggerDoc(__filename, '/docs')
		app.use app.router
		app.use express.errorHandler()

	

		###
		Start process from slug in new container

		:file - slug path
		:cmd - command to run
		:rendezvous - start in rendezvous mode
		:logApp - application name for loogging
		:logName - log name  

		###
		app.post '/ps/start', (req, res) ->
			slug = req.body.slug
			cmd = req.body.cmd
			env = req.body.env
			userEnv = req.body.userEnv 
			rendezvous = req.body.rendezvous
			logApp = req.body.logApp
			logName = req.body.logName
			# console.log '---------=-=-=-=-'
			# util.log util.inspect req.body
			return res.json error: 'Missing slug' unless slug

			lxc = new Lxc

			lxc.on 'data', (data) ->
				# util.print "dada " + data

			lxc.on 'error', (data) ->
				# util.print 'ERR: ' + data

			# lxc.on 'exit', (code) ->
			# 	util.print 'EXIT: ' + code

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
		
				if userEnv
					env.LXC_LINES = userEnv.LINES
					env.LXC_COLUMNS = userEnv.COLUMNS
			
				storage.getSlug slug, (err, tmp) ->
					exec "tar -C #{approot}/ -xzf #{tmp}", (error, stdout, stderr) ->
						fs.unlink tmp, () ->
						
					
						port = 5000
						env.PORT = port
						if rendezvous
							lxc.rendezvous '/buildpacks/startup /app run ' + cmd, env, (data) ->
								# console.log "::#{port}"
					
								pso = psmanager.add data.pid, lxc.name, lease.ip, data.port
								pso.rendezvousURI = "tcp://#{config.ip}:#{data.port}"
								res.json pso
						
						
						else
							lxc.exec '/buildpacks/startup /app run ' + cmd, env, (exitCode) ->
								lxc.dispose () ->
							ipInfo = lease.portMap[lease.ip]
							pso = psmanager.add lxc.process.pid, name, ipInfo.publicIp, ipInfo.publicPort 
							res.json pso

	
	

		###
		Kill process by pid
		###
		app.post '/ps/kill', (req, res) ->
			# util.log util.inspect req.body

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
	
			res.json 
				name: config.name
				id:	config.id
				ip: config.ip
				port: config.port
				containersCount: psmanager.getCount()
				motd: 'You bitch'
				processes: psmanager.pids
			# exec "ps #{req.query.pid}", (error, stdout, stderr) ->
			# 	res.end stdout

		## TEST
		app.get '/ps/statusall', (req, res) ->
			exec "ps afx", (error, stdout, stderr) ->
				res.end stdout



		app.post '/git/build', (req, res) ->
			p = req.body

			fileName = "#{p.repo}-#{p.branch}-#{p.rev}"
			slugName = "#{fileName}.tgz"

			process.env.TERM = 'xterm'
			callbackUrl = p.callbackUrl
		
			storage.getGitArchive "#{fileName}.tar.gz", (err, archive) ->
				return util.log util.inspect err if err
		
				util.log "Building #{p.repo} #{p.branch} #{p.rev}".green

				lxc = new Lxc

				exit = (exitCode) ->
					exitCode = 1 unless exitCode? 
					lxc.dispose ->
						util.log "Done #{p.repo} #{p.branch} #{p.rev} with code #{exitCode}".yellow
						res.end("94ed473f82c3d1791899c7a732fc8fd0_exit_#{exitCode}\n")


				lxc.on 'data', (data) ->
					res.write data

				lxc.on 'error', (data) ->
					res.write data


				lxc.setup dhcp.get(), (name)->
					approot = "#{lxc.root}app"
					fs.mkdirSync approot


					# Rozbalim zdrojaky z gitu do /app
					exec "tar -C #{approot}/ -xzf #{archive}", (error, stdout, stderr) ->
						# TODO unlink archive
						files = fs.readdirSync approot
						

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
							slug: slugName 
							procfile: procData

						env = {}
						env.LOG_CHANNEL = 'TODOkanalek'
						env.LOG_APP = 'TODOappka'
						env.LXC_RENDEZVOUS = 1
						# pustim buildpack
						lxc.exec '/buildpacks/startup /app', env, (exitCode) ->

							# zabalim slug do tempu
							# todo smazat slug
							slugTemp = "/tmp/#{fileName}.tar.gz"
							exec "tar -Pczf #{slugTemp} -C #{approot} .", (error, stdout, stderr) ->
							
								storage.putSlug slugTemp, slugName, (err) ->
									util.log util.inspect err if err
								
									stat = fs.statSync slugTemp
									buildData.slugSize = stat.size
									fs.unlink slugTemp, () ->
								
									procTypes = []
									procTypes.push key for key, val of procData
									res.write "> Procfile declares types -> #{procTypes.join ' '}\n"
									res.write "> Compiled slug size: #{filesize(buildData.slugSize)}\n"
					
									request {uri: callbackUrl, method: 'POST', json: buildData}, (err, response, body) ->
										throw err if err
										if body?.status isnt 'ok'
											res.write "ERR: Couldn't save build on api\n"
											res.write util.inspect body
											res.write "\n"
											return exit 1

										res.write "> Build stored: v#{body.version}\n"
										exit exitCode



		app.listen config.port
		util.log "Toadwart \"#{config.name}\" serving on #{config.port}".yellow

