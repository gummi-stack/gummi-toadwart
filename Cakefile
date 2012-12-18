util = require 'util'
{exec} = require 'child_process'

cmd = (host, cmd, done) ->
	exec "ssh #{host} 'sudo  -E bash -c \"source /opt/nvm/nvm.sh && #{cmd}\"'", (err, stdout, stderr) ->
		util.log err if err
		util.log stderr if stderr
		# util.log stdout if stdout
		util.log "#{host}: #{stdout}"
		done?()
		
task 'deploy', ->
	hosts = [
		'node2.lxc.nag.ccl'
		'node3.lxc.nag.ccl'
	]
	host = hosts[1]
	for host in hosts
		do (host) ->
			cmd host, 'npm install http://github.com/gummi-stack/gummi-toadwart/tarball/master -g --silent', () ->
				cmd host, 'supervisorctl restart toadwart', (oo) ->
		
	util.log 'ddd'