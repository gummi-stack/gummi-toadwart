exec = require('child_process').exec
fs   = require 'fs'
uuid = require 'node-uuid'
key  = "#{__dirname}/id_dsa"
tar  = require 'tar'
zlib = require 'zlib'
knox = require 'knox'
pack = tar.Pack()
MultiPartUpload = require 'knox-mpu'
fs.chmodSync key, 0o600


module.exports = (location) ->
	get = (from, to, done) ->
		return done 'storage.get() not implenented yet'

		cmd = "scp -o StrictHostKeyChecking=no -i #{key} #{location}:#{from} #{to}"
		# console.log cmd
		exec cmd, (err, stdout, stderr) ->
			er = err or stderr
			done er, to


	put = (from, to, done) ->
		try
			client = knox.createClient process.config.s3
		catch e
			return cb e

		gzip = zlib.Gzip()

		reader = fstream.Reader({ path: from, type: 'Directory' })

		reader.once 'error', cb
		reader.on 'error', () ->

		reader.pipe(tar.Pack())
			.pipe(gzip)

		upload = new MultiPartUpload
			client: client
			objectName: to
			stream: gzip
		, cb

	getGitArchive: (name, done) ->
		get "git/#{name}", "/tmp/#{name}-#{uuid.v4()}", done

	putSlug: (path, name, done) ->
		put path, "slugs/#{name}", done

	getSlug: (name, done) ->
		get "slugs/#{name}", "/tmp/#{name}-#{uuid.v4()}", done

