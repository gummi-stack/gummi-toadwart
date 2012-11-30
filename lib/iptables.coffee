{spawn, fork, exec} = require('child_process')
util = require 'util'
# 
# chain = 'TOADWART'
# 
# iptables = (args, done) ->
# 	cmd = "iptables #{args}"
# 	exec cmd, (err, stdout, stderr) ->
# 		done stdout or stderr
# 		
# getVersion = (done) ->	
# 	iptables '--version', (out) ->
# 		v = out?.match? /(v\d+.\d+.\d+)/
# 		done v?[0]
# 
# 
# resetChain = (done) ->
# 	iptables "-t nat -X #{chain}", () ->
# 		iptables "-t nat -N #{chain}", () ->
# 			
# 			iptables -t filter -D INPUT -j fun-filter
# 			
# 			done()
# 	
# 
# getVersion (version) ->
# 	return util.log "Iptables not found!" unless version
# 	util.log "Iptables #{version} found"
# 
# 	resetChain () ->
# 		
# 
# return
# process.exit 1
# 
# tables = ['filter','nat','mangle']
# 
# getTable = (table) ->
# 	o =
# 		addChain: (chain) ->
# 			console.log table + " " + chain
# 					
# 	() ->
# 		o
# 		
# 		
# 
# for table in tables
# 	exports.__defineGetter__ table, getTable table
# 	