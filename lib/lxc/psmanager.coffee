fs = require 'fs'
async = require 'async'
util = require 'util'
uuid = require 'node-uuid'
colors = require 'colors'
{exec} = require 'child_process'
{EventEmitter} = require 'events'
Syslog = require 'syslog-stream'

syslog = new Syslog "GUMMI"

delay = (ms, func) -> setTimeout func, ms

module.exports = class PsManager extends EventEmitter
	constructor: (@config) ->

		@temp = '/var/run/toadwart'
		try
			fs.mkdirSync @temp
		catch err

		@pids = {}

		@loadPids()
	run: () =>
		@checkPids()

	add: (pid, name, ip, port, env) ->
		p =
			pid: pid
			name: name
			uuid: uuid.v4()
			toadwartName: @config.name
			toadwartId: @config.id
			ip: ip
			port: port
			env: env

		util.log "Started ".green + p.pid + "\t" + p.name


		# "host_name" => "string",
		# "source" => "string",
		# "app" => "string",
		# "branch" => "string",
		# "worker" => "string",
		# "output" => "integer",
		# "json" => "json" # & plain data into field message
		#
		#
		# env.LOG_APP = repo.replace(/\.git$/, '') #.replace ':', '/'
		# env.LOG_BRANCH = branch
		# env.LOG_SOURCE = "gummi"
		# env.LOG_WORKER = req.body.worker.replace '-', '.'

		syslog.info "#{env.LOG_SOURCE} #{env.LOG_APP} #{env.LOG_BRANCH} #{env.LOG_WORKER} 1 Starting containerxxx"

		# util.log util.inspect p

		fs.writeFileSync "#{@temp}/#{pid}", JSON.stringify p
		@pids[pid] = p

		p

	getCount: =>
		cnt = 0
		cnt++ for x of @pids
		cnt

	remove: (pid) =>
		util.log "Stopped ".yellow + pid

		unless @pids[pid]
			util.log "#{pid} neni muj".red
			return

		env = @pids[pid].env
		syslog.info "#{env.LOG_SOURCE} #{env.LOG_APP} #{env.LOG_BRANCH} #{env.LOG_WORKER} 1 Stopping container"

		@emit 'remove', @pids[pid]


		delete @pids[pid]
		try
			fs.unlinkSync "#{@temp}/#{pid}"
		catch err
			util.log err

	loadStats: (done) ->
		async.each Object.keys(@pids), (pid, next) =>
			p = @pids[pid]
			name = p.name
			fs.readFile "/sys/fs/cgroup/memory/lxc/#{name}/memory.usage_in_bytes", "utf8", (err, usage) ->
				fs.readFile "/sys/fs/cgroup/cpuacct/lxc/#{name}/cpuacct.stat", "utf8", (err, cpu) ->
					p.rss = parseInt usage.trim() if usage
					p.cpu = {}
					if cpu
						lines = cpu.split "\n"
						for line in lines
							[key, val] = line.split " "
							p.cpu[key] = val

					next()
		, () =>
			done null, @pids




	loadPids: () ->
		files = fs.readdirSync @temp

		for pid in files
			@pids[pid] = JSON.parse fs.readFileSync("#{@temp}/#{pid}").toString()

		util.log "Loaded #{Object.keys(@pids).length} pids".green

	checkPids: () =>

		exec "ps aux | grep manage-ephemeral | awk '{print $2}'", (error, stdout, stderr) =>
			runningPids = stdout.split "\n"

			for pid, name of @pids
				if runningPids.indexOf(pid) is -1
					@remove pid

			delay 1000, @checkPids
