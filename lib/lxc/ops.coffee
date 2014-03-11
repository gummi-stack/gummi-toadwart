util = require 'util'
fs = require 'fs'
exec = require('child_process').exec
procfile = require 'procfile'
request = require 'request'
filesize = require 'filesize'
Lxc = require './lxc'
PsManager = require './psmanager'
express = require 'express'
config = process.config
cson = require 'cson'

psmanager = new PsManager config
psmanager.on 'remove', (info) ->
	# util.log "Cleaning lxc #{info.name}"
	lxc = new Lxc info.name
	lxc.dispose()

psmanager.run()

module.exports = (app, dhcp, storage) ->
	app.use (req, res, next)->
		console.log "#{req.method} #{req.path}"
		next()
	###
	Start process from slug in new container

	:file - slug path
	:cmd - command to run
	:rendezvous - start in rendezvous mode
	:logApp - application name for loogging
	:logName - log name

	###
	app.post '/ps/start', express.json(), (req, res, next) ->
		console.log JSON.stringify req.body
		console.log "API START #{req.body.name}".green
		slug = req.body.slug
		cmd = req.body.cmd
		env = req.body.env
		env ?= {}
		userEnv = req.body.userEnv
		rendezvous = req.body.rendezvous
		# logApp = req.body.logApp
		# logUuid = req.body.logUuid
		# dynoUuid = req.body.dynoUuid
		hostname = req.body.hostname


		# console.log '---------=-=-=-=-'
		# util.log util.inspect req.body
		return res.json error: 'Missing slug' unless slug

		lxc = new Lxc

		lxc.on 'data', (data) ->
			util.print "dada " + data

		lxc.on 'error', (data) ->
			util.print 'ERR: ' + data

			# lxc.on 'exit', (code) ->
			# 	util.print 'EXIT: ' + code

		lease = dhcp.get()
		lxc.setup lease, hostname, (err, name) ->

			return next err if err

			approot = "#{lxc.root}app"
			try
				fs.mkdirSync approot # todo vazne ignorovat?
			catch err

			# file = req.query.slug
			# env = JSON.parse req.query.env
			# cmd = req.query.cmd
			# console.log "tar -C #{approot}/ -xzf #{file}"
			# for key, val of env
			# 		    util.log key, val
			# 		    process.env[key] = val

			# env.LOG_CHANNEL = logName

			[repo, branch] = req.body.name.split '/'

			lxc.env.LOG_APP = repo.replace(/\.git$/, '') #.replace ':', '/'
			lxc.env.LOG_BRANCH = branch
			lxc.env.LOG_SOURCE = "gummi"
			lxc.env.LOG_WORKER = req.body.worker.replace '-', '.'
			env.TERM = "xterm"

			# env.LOG_APP = req.body.logApp
			# env.LOG_CMD = req.body.cmd
			#
			# env.LOG_UUID = logUuid
			# env.DYNO_UUID = dynoUuid
			# env.GUMMI_ID = config.id

			# console.log " =---=-=-= " + env.DYNO_UUID

			if userEnv
				env.LXC_LINES = userEnv.LINES
				env.LXC_COLUMNS = userEnv.COLUMNS

			storage.getSlug slug.Location, approot, (err) ->
				return next err if err
				# exec "tar -C #{approot}/ -xzf #{tmp}", (error, stdout, stderr) ->
				# 	util.log util.inspect error if error
				# 	util.log util.inspect stderr if stderr
				#
				# 	fs.unlink tmp, () ->
				#
				#
				port = lease.port
				env.PORT = port
				# console.log "PPPPPP---", port
				if rendezvous
					console.log "EEEEE", cmd, env

					lxc.rendezvous cmd, env, (data) ->
						# console.log "::#{port}"
						pso = psmanager.add data.pid, lxc.name, lease.ip, data.port, lxc.env
						# pso.rendezvousPort = "#{data.port}"
						# pso.rendezvousURI = "tcp://#{config.ip}:#{data.port}"
						res.json pso


				else
					console.log '----c-c-c-c'
					# util.log util.inspect env
					#							lxc.exec '/buildpacks/startup /app run ' + cmd, env, (exitCode) ->
					lxc.exec cmd, env, (exitCode) ->
						lxc.dispose () ->
					ipInfo = lease.portMap[lease.ip]
					pso = psmanager.add lxc.process.pid, name, ipInfo.publicIp, ipInfo.publicPort, lxc.env
					res.json pso


	###
	Kill process by pid
	###
	app.post '/ps/kill', express.json(),  (req, res) ->
		console.log "API kill".red

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
		psmanager.loadStats (err, stats) ->
			res.json
				name: config.name
				id: config.id
				# ip: config.ip
				port: config.port
				containersCount: psmanager.getCount()
				motd: 'You bitch'
				processes: stats
	# exec "ps #{req.query.pid}", (error, stdout, stderr) ->
	# 	res.end stdout

	## TEST
	app.get '/ps/statusall', (req, res) ->
		exec "ps afx", (error, stdout, stderr) ->
			res.end stdout


	app.post '/git/build', (req, res, next) ->
		data = try JSON.parse req.headers['x-data']
		return next "Invalid x-data" unless data

		write = (message) ->

			m = JSON.stringify(msg: message.toString()) + "\n"
			res.write m


		p = data


		fileName = "#{p.repo}-#{p.branch}-#{p.rev}"
		slugName = "#{fileName}.tgz"
		cacheName = "#{p.repo}-#{p.branch}-cache.tgz"
		hostname = p.hostname
		process.env.TERM = 'xterm'
		callbackUrl = p.callbackUrl


		# storage.getGitArchive "#{fileName}.tar.gz", (err, archive) ->
	# 		return util.log util.inspect err if err


		util.log "Building #{p.repo} #{p.branch} #{p.rev}".green

		lxc = new Lxc

		exit = (exitCode) ->
			exitCode = 1 unless exitCode?
			lxc.dispose ->
				util.log "Done #{p.repo} #{p.branch} #{p.rev} with code #{exitCode}".yellow
				res.end JSON.stringify exitCode: exitCode


		lxc.on 'data', (data) ->
			write data

		lxc.on 'error', (data) ->
			write data


		req.pause()

		lxc.setup dhcp.get(), hostname, (err, name)->



			return next err if err
			# console.log 'lx test
			# '
			approot = "#{lxc.root}app"
			try
				fs.mkdirSync approot  #todo asi by se to melo hlidat
			catch err

			cachedir = "#{lxc.root}tmp/buildpack-cache"
			try
				fs.mkdirSync cachedir
			catch err

			#mam adresar
			# console.log approot




					#
			# req.on 'data', (d) ->
			# 	console.log d
			# req.on 'error', (err) ->
			# 	return next err
			# req.on 'end', () ->
			# 	res.json 'xx'
			zlib = require 'zlib'
			tar = require 'tar'
			gzip = zlib.createGunzip()

			req.resume()

			# xx = req.pipe(gzip).pipe process.stdout #.pipe(tar.Extract(approot))
			# xx = req.pipe(gzip) #.pipe(tar.Extract(approot))
			fs = require 'fs'
			# gzip = fs.createWriteStream '/tmp/aaa.tar.gz'

			tarx = tar.Extract(approot)
			xx = req.pipe(gzip).pipe(tarx)


			gzip.on 'error', (err) ->
				return next err
			tarx.on 'error', (err) ->
				return next err

			tarx.on 'end', () ->
				#
				# storage.getSlug cacheName, (err, tmp1) ->
				# 	exec "tar -C #{cachedir}/ -xzf #{tmp1}", (error, stdout, stderr) ->
				#
				# 		# Rozbalim zdrojaky z gitu do /app
				# 		exec "tar -C #{approot}/ -xzf #{archive}", (error, stdout, stderr) ->
				# 			# TODO unlink archive
				# 			files = fs.readdirSync approot
				#
				#
				try
					procData = fs.readFileSync("#{approot}/Procfile").toString()
					procData = procfile.parse procData

				catch e
					write "ERR: Missing procfile\n"
					return exit 1


				buildData =
					app: p.repo
					branch: p.branch
					rev: p.rev
					timestamp: new Date
					slug: slugName
					procfile: procData

				env = {}

				console.log buildData
				env.LOG_APP = buildData.app.replace(/\.git$/, '') #.replace ':', '/'
				env.LOG_BRANCH = buildData.branch
				env.LOG_SOURCE = "deploy"
				env.LOG_WORKER = "git-build"

				# # env.LOG_SOURCE= "repo"


				# env.LOG_CHANNEL = 'TODOkanalek'
				# env.LOG_APP = 'TODOappka'
				lxc.env.LXC_RENDEZVOUS = 1
				lxc.env.TERM = 'xterm'
				env.TERM = 'xterm'
				# env.REPO = p.repo
				# env.BRANCH = p.branch
				env.REV = p.rev
				# console.log env

				# pustim buildpack
				lxc.exec '/init/buildpack', env, (exitCode) ->
					lxc.removeAllListeners()
					return exit exitCode unless exitCode is 0

					buffer = ""
					lxc.on 'data', (data) ->
						buffer += data

					lxc.on 'err', (data) ->
						buffer += data

					lxc.exec '/init/buildpack release', env, (exitCode) ->
						console.log "Buildpack release failed #{exitCode}".red if exitCode
						console.log "oxoxxoxoxoxoxo"
						console.log buffer
						console.log "oxoxxoxoxoxoxo"
						return exit exitCode unless exitCode is 0
						cson.parse buffer, (err, releaseInfo) ->
							if err
								console.log err
								return exit 1
							console.log releaseInfo

							buildData.releaseData = releaseInfo

							write "-----> Compressing and publishing slug... \n"

							storage.putSlug approot, slugName, (err, s3info) ->
								if err
									console.log err
									res.write JSON.stringify(error: err) + "\n"
									return next err


								buildData.slug = s3info

								console.log buildData
								procTypes = []
								procTypes.push key for key, val of procData
								write "-----> Procfile declares types -> #{procTypes.join ' '}\n"
								write "-----> Compiled slug size: #{filesize buildData.slug.size}\n"
								console.log JSON.stringify(result: buildData) + "\n"
								res.write JSON.stringify(result: buildData) + "\n"
								res.end()

