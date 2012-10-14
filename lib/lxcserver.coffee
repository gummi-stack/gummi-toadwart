util = require 'util'
net = require 'net'

command = process.argv[2]
name = process.argv[3]

manager = __dirname + "/../manage-ephemeral.sh"
server = net.createServer (socket) =>
	pty = require 'pty.js'
	
	console.log '4343434343434343434343434'
	util.log util.inspect process.env
	
	# term = pty.spawn 'bash', [], {
	# term = pty.spawn manager, ['run', @name, '--', command], {
	#term = pty.spawn xmanager, [], {
	term = pty.spawn 'su', ['-c', manager + ' run ' + name + ' -- ' +  command], {
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

server.listen null, ->
	process.send "#{server.address().port}"
