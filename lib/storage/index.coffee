exec = require('child_process').exec
fs   = require 'fs'
uuid = require 'node-uuid'
tar  = require 'tar'
zlib = require 'zlib'
knox = require 'knox'
fstream = require 'fstream'
MultiPartUpload = require 'knox-mpu'



module.exports = (location) ->
	get = (from, to, done) ->
		return done 'storage.get() not implenented yet'

		# cmd = "scp -o StrictHostKeyChecking=no -i #{key} #{location}:#{from} #{to}"
		# # console.log cmd
		# exec cmd, (err, stdout, stderr) ->
		# 	er = err or stderr
		# 	done er, to


	put = (from, to, done) ->
		try
			client = knox.createClient process.config.s3
		catch e
			return done e

		gzip = zlib.Gzip()

		reader = fstream.Reader({ path: from, type: 'Directory' })

		reader.once 'error', done
		reader.on 'error', () ->

		reader.pipe(tar.Pack())
			.pipe(gzip)

		upload = new MultiPartUpload
			client: client
			objectName: to
			stream: gzip
		, done

	getGitArchive: (name, done) ->
		get "git/#{name}", "/tmp/#{name}-#{uuid.v4()}", done

	putSlug: (path, name, done) ->
		put path, "slugs/#{name}", done

	getSlug: (name, done) ->
		get "slugs/#{name}", "/tmp/#{name}-#{uuid.v4()}", done

