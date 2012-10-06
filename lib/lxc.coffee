express = require 'express'
util = require 'util'
fs = require 'fs'
net = require 'net'
EventEmitter = require('events').EventEmitter
{fork, exec} = require('child_process')

manager = __dirname + "/../manage-ephemeral.sh"

## TODO sanitize command && ; " etc...  just path

class Lxc extends EventEmitter
	constructor: ->

	setup: (cb) =>
		exec "#{manager} setup", (err, stdout, stderr) =>
			@name = '' + stdout
			@name = @name.replace "\n", ""
			@root = "/var/lib/lxc/#{@name}/rootfs/"
			cb @name
			

	exec: (command, cb) =>
		util.log util.inspect [manager, @name, command]
		p = spawn 'setsid', [manager, 'run', @name, '--', command]
		p.stdout.on 'data', (data) =>
			@emit 'data', data
		p.stderr.on 'data', (data) =>
			@emit 'error', data

		p.on 'exit', (code) =>
			@emit 'exit', code
			cb( code )
		@process = p
	
	rendezvous: (command, cb) =>
		child = fork __dirname + '/lxcserver', [command, @name]
		child.on 'message', cb

	dispose: (cb) =>
		exec "#{manager} clean #{@name}", (err, stdout, stderr) =>
			cb()
		
module.exports = Lxc
