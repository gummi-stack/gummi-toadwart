fs   = require 'fs'
tar  = require 'tar'
zlib = require 'zlib'
knox = require 'knox'
fstream = require 'fstream'
request = require 'request'
fscache = require 'fs-cache'
MultiPartUpload = require 'knox-mpu'


cache = fscache '/tmp/toadwart-slugs/'


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

		console.log 'xxxxx22222'
		upload = new MultiPartUpload
			client: client
			objectName: to
			stream: gzip
		, done

	putSlug: (path, name, done) ->
		put path, "slugs/#{name}", done


	getSlug: (url, dest, done) ->
		timeout = 60 * 60 * 24
		cachedUrlStream = (url) ->
			if cache.exists url
				console.log "From cache #{url} to #{dest}"
				return cache.get(url, expire: timeout)

			console.log "Downloading #{url} to #{dest}"
			r = request(url)
			r.pipe cache.put(url, expire: timeout)
			r



		gunzip = zlib.Gunzip()
		untar = tar.Extract
			path: dest
			strip: 1

		req = cachedUrlStream url
		req.pipe(gunzip).pipe(untar)

		req.on 'error', (err) ->
			done err
		untar.on 'end', () ->
			done()
