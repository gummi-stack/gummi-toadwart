fs 		= require 'fs'
exec	= require('child_process').exec
util	= require 'util'
uuid	= require 'node-uuid'
colors	= require 'colors'
EventEmiter = require('events').EventEmitter

delay = (ms, func) -> setTimeout func, ms

module.exports = class PsManager extends EventEmiter
	constructor: (@config) ->
		
		@temp = '/var/run/toadwart'
		try
			fs.mkdirSync @temp
		catch err
		
		@pids = {}
		
		@loadPids()
	run: () =>
		@checkPids()
		
	add: (pid, name, ip, port) ->
		p = 
			pid: pid
			name: name
			uuid: uuid.v4()
			toadwartName: @config.name
			toadwartId: @config.id
			ip: ip
			port: port
		
		util.log "Started ".green + p.pid + "\t" + p.name
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
			
		@emit 'remove', @pids[pid]
		
		delete @pids[pid]
		try
			fs.unlinkSync "#{@temp}/#{pid}"
		catch err
			util.log err
		
	loadPids: () ->
		files = fs.readdirSync @temp
		
		for pid in files
			@pids[pid] = JSON.parse fs.readFileSync("#{@temp}/#{pid}").toString()

	checkPids: () =>

		exec "ps aux | grep manage-ephemeral | awk '{print $2}'", (error, stdout, stderr) =>
			runningPids = stdout.split "\n"
	
			for pid, name of @pids 
				if runningPids.indexOf(pid) is -1
					@remove pid
		
			delay 1000, @checkPids
		