exec = require('child_process').exec
fs = require 'fs'
uuid = require 'node-uuid'
key = "#{__dirname}/id_dsa"
fs.chmodSync key, 0o600

module.exports = (location) ->
	get = (from, to, done) ->
		cmd = "scp -o StrictHostKeyChecking=no -i #{key} #{location}:#{from} #{to}"
		# console.log cmd
		exec cmd, (err, stdout, stderr) ->
			er = err or stderr
			done er, to


	put = (from, to, done) ->
		cmd = "cat #{from} | ssh -o StrictHostKeyChecking=no -i #{key} #{location} \"cat - > #{to}\""
		# console.log cmd
		exec cmd, (err, stdout, stderr) ->
			er = err or stderr
			done err, to

	getGitArchive: (name, done) ->
		get "git/#{name}", "/tmp/#{name}-#{uuid.v4()}", done

	putSlug: (path, name, done) ->
		put path, "slugs/#{name}", done

	getSlug: (name, done) ->
		get "slugs/#{name}", "/tmp/#{name}-#{uuid.v4()}", done

