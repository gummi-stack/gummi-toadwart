express = require 'express'
util = require 'util'
fs = require 'fs'
net = require 'net'
EventEmitter = require('events').EventEmitter
{spawn, fork, exec} = require('child_process')

manager = __dirname + "/../manage-ephemeral.sh"

## TODO sanitize command && ; " etc...  just path

class Lxc extends EventEmitter
	constructor: ( @name ) ->

	setup: (lan, cb) =>
		exec "LXC_IP=#{lan.ip} LXC_MASK=#{lan.mask} LXC_ROUTE=#{lan.route} #{manager} setup", (err, stdout, stderr) =>
			@name = '' + stdout
			@name = @name.replace "\n", ""
			@root = "/var/lib/lxc/#{@name}/rootfs/"
			
			# util.log stdout
			# util.log stderr
			
			cb @name
			

	exec: (command, env, cb) =>
		p = spawn 'setsid', [manager, 'run', @name, '--', command], {env: env}
#		logr = spawn '/root/rlogr/rlogr', ['-t', '-s test2']
		
#		p.stdout.pipe logr.stdin, {end: yes}
#		logr.stdin.resume()

#		logr.on 'exit', (code) =>
#			util.log 'xxxxxxxxxxxx ' + code

		
		p.stdout.on 'data', (data) =>
			# util.log data
			@emit 'data', data
		p.stderr.on 'data', (data) =>
			# util.log data
			@emit 'error', data

		p.on 'exit', (code) =>
			@emit 'exit', code
			cb( code )
		@process = p


	rendezvous: (command, env,cb) =>
		env.LXC_RENDEZVOUS = 1
		child = fork __dirname + '/lxcserver', [command, @name], {env: env}
		# child.stdout.on 'data', (data) =>
		# 	util.log '>>>>>>>> ' + data
			
		child.on 'message', (data) ->
			util.log "$$$$$$$ " + data
			cb JSON.parse data
			
		@process = child

	dispose: (cb) =>
		exec "#{manager} clean #{@name}", (err, stdout, stderr) =>
			cb()
		
module.exports = Lxc
