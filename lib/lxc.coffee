express = require 'express'
util = require 'util'
fs = require 'fs'
net = require 'net'
{spawn, exec} = require('child_process')

manager = __dirname + "/../manage-ephemeral.sh"

## TODO sanitize command && ; " etc...  just path

class Lxc
	constructor: ->

	setup: (cb) =>
		exec "#{manager} setup", (err, stdout, stderr) =>
			@name = '' + stdout
			@name = @name.replace "\n", ""
			@root = "/var/lib/lxc/#{@name}/rootfs/"
			cb @name
			

	exec: (command, cb) =>
		p = spawn 'setsid', [manager, 'run', @name, '--', command]
		p.stdout.on 'data', (data) ->
			util.log 'stdout ' + data
		p.stderr.on 'data', (data) ->
			util.log 'stderr ' + data

		p.on 'exit', (code) =>
			util.log code  + ' ---konec'
			cb()
		@process = p
	
	rendezvous: (command, cb) =>
		server = net.createServer (socket) =>
			pty = require 'pty.js'
			
			xmanager = __dirname + "/../start-ephemeral"
			
			
			# term = pty.spawn 'bash', [], {
			# term = pty.spawn manager, ['run', @name, '--', command], {
			#term = pty.spawn xmanager, [], {
			term = pty.spawn 'su', ['-c', manager + ' run ' + @name + ' -- ' +  command], {
				name: 'xterm-color',
				cols: 80,
				rows: 50,
				# cwd: process.env.HOME,
				# env: process.env
			}

			handleTermData = (data) -> 
				socket.write data
			
			term.on 'data', handleTermData

			term.on 'exit', ->
				socket.end()

			socket.on 'data', (data) ->
				term.write data
		
			socket.on 'end', ->
				term.removeListener 'data', handleTermData #jinak to pri ukonceni padne
				term.kill 'SIGKILL'
				term.end()
				util.log 'client disconnected'
				cb()
		
		server.listen()
		return server.address().port
		
	dispose: (cb) =>
		exec "#{manager} clean #{@name}", (err, stdout, stderr) =>
			cb()
		
module.exports = Lxc	