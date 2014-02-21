exec = require('child_process').exec
fs   = require 'fs'
uuid = require 'node-uuid'
tar  = require 'tar'
zlib = require 'zlib'
knox = require 'knox'
fstream = require 'fstream'
request = require 'request'
MultiPartUpload = require 'knox-mpu'



module.exports = (location) ->


	put = (from, to, done) ->
		try
			client = knox.createClient process.config.s3
		catch e
			return done e

		gzip = zlib.Gzip()

		reader = fstream.Reader({ path: from, type: 'Directory' })

		reader.once 'error', done
		reader.on 'error', () -> ## suppress other errors

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

	# getSlug: (name, done) ->
	# 	get "slugs/#{name}", "/tmp/#{name}-#{uuid.v4()}", done


	getSlug: (url, dest, done) ->
		console.log "Downloading #{url} to #{dest}"
		gunzip = zlib.Gunzip()
		untar = tar.Extract
			path: dest
			strip: 1

		req = request.get(url)
		req.pipe(gunzip).pipe(untar)

		req.on 'error', (err) ->
			done err
		untar.on 'end', () ->
			done()

		# return done 'storage.get() not implenented yet'

		# cmd = "scp -o StrictHostKeyChecking=no -i #{key} #{location}:#{from} #{to}"
		# # console.log cmd
		# exec cmd, (err, stdout, stderr) ->
		# 	er = err or stderr
		# 	done er, to
