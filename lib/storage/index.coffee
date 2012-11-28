{exec} = require('child_process')
fs = require 'fs'

key = "#{__dirname}/id_dsa"
fs.chmodSync key, 0o600

get = (from, to, done) ->
	cmd = "scp -o StrictHostKeyChecking=no -i #{key} cdn@10.1.69.105:#{from} #{to}"
	# console.log cmd
	exec cmd, (err, stdout, stderr) ->
		er = err or stderr
		done er, to


put = (from, to, done) ->
	cmd = "cat #{from} | ssh -o StrictHostKeyChecking=no -i #{key} cdn@10.1.69.105 \"cat - > #{to}\""
	# console.log cmd
	exec cmd, (err, stdout, stderr) ->
		er = err or stderr
		done err, to

exports.getGitArchive = (name, done) ->
	get "git/#{name}", "/tmp/#{name}", done

exports.putSlug = (path, name, done) ->
	put path, "slugs/#{name}", done

exports.getSlug = (name, done) ->
	get "slugs/#{name}", "/tmp/#{name}", done
	
	