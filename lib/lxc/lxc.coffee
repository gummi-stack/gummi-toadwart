util = require 'util'
EventEmitter = require('events').EventEmitter
{spawn, fork, exec} = require('child_process')

manager = __dirname + "/manage-ephemeral.sh"

## TODO sanitize command && ; " etc...  just path

class Lxc extends EventEmitter
	constructor: ( @name ) ->

	setup: (lan, name, cb) =>
		env =
			LXC_IP: lan.ip
			LXC_MASK: lan.mask
			LXC_ROUTE: lan.route

		# process.env.PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games"
		exec "#{manager} setup #{name}", env: env, (err, stdout, stderr) =>
			return cb err if err

			@name = name
			@name = @name.replace "\n", ""
			@root = "/var/lib/lxc/#{@name}/rootfs/"

			console.log 'setup', 'stdout', stdout
			# console.log 'setup', 'stderr', stderr

			cb null, @name


	exec: (command, env, cb) =>
		env.TEMP_PATH = env.PATH
		env.PATH = process.env.PATH
		# util.log '-ev-ev-e-ve-ve-'
		# util.log util.inspect env
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
			@emit 'data', data

		p.on 'exit', (code) =>
			@emit 'exit', code
			cb( code )
		@process = p


	rendezvous: (command, env,cb) =>
		env.LXC_RENDEZVOUS = 1
		env.TEMP_PATH = env.PATH
		env.PATH = process.env.PATH

		util.log util.inspect env
		child = fork __dirname + '/lxcserver', [command, @name], {env: env}
		# child.stdout.on 'data', (data) =>
		# 	util.log '>>>>>>>> ' + data

		child.on 'message', (data) ->
			# util.log "$$$$$$$ " + data
			cb JSON.parse data

		@process = child

	dispose: (cb = ->) =>
		exec "#{manager} clean #{@name}", cb

module.exports = Lxc
