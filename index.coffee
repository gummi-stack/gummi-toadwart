express = require 'express'
util = require 'util'
fs = require 'fs'
{spawn, exec} = require('child_process')
net = require 'net'
procfile = require 'procfile'

dhcp = new require('./lib/dhcp.coffee')
	addresses: '10.1.69.50-10.1.69.99'
	mask: '255.255.255.0'
	route: '10.1.69.254'

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



app = express()
app.use express.bodyParser()

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

		###### TODO rozbalit appku
		lxc.setup dhcp.get(), (name) ->
			util.log "lxc name #{name}"
			lxc.rendezvous command, (port) ->
				console.log "::#{port}"
				res.send rendezvousURI: "tcp://10.1.69.105:#{port}"


app.post '/ps/start', (req, res) ->
	file = req.body.slug
	cmd = req.body.cmd
	env = req.body.env

	return res.json error: 'Missing slug' unless file

	lxc = new Lxc

	lxc.on 'data', (data) ->
		util.print "dada " + data

	lxc.on 'error', (data) ->
		util.print 'ERR: ' + data

	lxc.on 'exit', (code) ->
		util.print 'EXIT: ' + code

	lxc.setup dhcp.get(), (name) ->
		approot = "#{lxc.root}app"
		fs.mkdirSync approot

		# file = req.query.slug
		# env = JSON.parse req.query.env
		# cmd = req.query.cmd
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

app.get '/ps/kill', (req, res) ->
	process.kill(req.query.pid * -1)
	lxc = new Lxc req.query.name
	lxc.dispose () ->
		res.end 'je po nem Jime'


app.get '/ps/status', (req, res) ->
	exec "ps #{req.query.pid}", (error, stdout, stderr) ->
		res.end stdout

app.get '/ps/statusall', (req, res) ->
	exec "ps afx", (error, stdout, stderr) ->
		res.end stdout




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
			#res.write "lxc name #{name}\n"

			util.log
			approot = "#{lxc.root}app"
			fs.mkdirSync approot

			util.log "tar -C #{approot} -xvzf #{file}"
			#res.write util.inspect process.env
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

				lxc.exec '/buildpacks/startup /app', (exitCode) ->
					exec "tar -Pczf #{slug} -C #{approot} .", (error, stdout, stderr) ->
						mongoFactory.db mongoUrl, (err, db) ->
							db.collection 'builds', (err, collection) ->
								collection.insert buildData

						exit exitCode

		exit = (exitCode) ->
			lxc.dispose ->
				res.end("94ed473f82c3d1791899c7a732fc8fd0_exit_#{exitCode}\n")


app.listen 81
util.log 'Toadwart serving on w81'

