util = require 'util'
net = require 'net'
portfinder = require 'portfinder'

command = process.argv[2]
name = process.argv[3]

manager = __dirname + "/manage-ephemeral.sh"
pid = 0

pty = require 'pty.js'

rows = parseInt(process.env.LXC_LINES) || 40
cols = parseInt(process.env.LXC_COLUMNS) || 80
# console.log 'spsp ' + process.env.PATH
# console.log 'su', ['-c', manager + ' run ' + name + ' -- ' +  command]
term = pty.spawn 'su', ['-c', manager + ' run ' + name + ' -- ' +  command], {
	name: 'xterm-color',
	cols: cols,
	rows: rows,
	env: process.env
}

term.pause()

server = net.createServer (socket) =>

	# console.log '4343434343434343434343434'
	# util.log util.inspect process.env

	# term = pty.spawn 'bash', [], {
	# term = pty.spawn manager, ['run', @name, '--', command], {
	#term = pty.spawn xmanager, [], {
		#p = spawn 'setsid', [manager, 'run', @name, '--', command], {env: env}


	#pid = term.pid

	#util.log "Spawn pid " + pid
	socket.write 'pojd do me <mackni enter> '

	term.resume()


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


portfinder.basePort = 6000
portfinder.getPort (err, port) ->
	if err
		console.log err
		process.exit 1

	server.listen port, ->
		# console.log

		process.send JSON.stringify
			port: server.address().port
			pid: term.pid
