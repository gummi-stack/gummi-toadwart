knox = require 'knox'
request = require 'request'
fscache = require 'fs-cache'
MultiPartUpload = require 'knox-mpu'
{spawn} = require 'child_process'


cache = fscache '/tmp/toadwart-slugs/'


isDownloading = {}


module.exports = (location) ->
	put = (from, to, done) ->
		try
			client = knox.createClient process.config.s3
		catch e
			return done e

		untar = spawn 'tar', ['-cz', from]

		untar.stderr.on 'data', (data) ->
			console.log 'pack:', data

		untar.on 'close', (code) ->
			return done() if code is 0
			done "Failed to pack #{from}. Exit code: #{code}"

		console.log 'xxxxx22222'
		upload = new MultiPartUpload
			client: client
			objectName: to
			stream: untar.stdout
		, done


	putSlug: (path, name, done) ->
		put path, "slugs/#{name}", done


	getSlug: (url, dest, done) ->
		if isDownloading[url] and Array.isArray isDownloading[url]
			isDownloading[url].push done
			return

		isDownloading[url] = [done]

		b = new Date
		timeout = 60 * 60 * 24
		cachedUrlStream = (url) ->
			if cache.exists url
				console.log "From cache #{url} to #{dest}"
				return cache.get(url, expire: timeout)

			console.log "Downloading #{url} to #{dest}"
			r = request(url)
			r.pipe cache.put(url, expire: timeout)
			r

		untar = spawn 'tar', ['--strip=1', '-xzC', dest]

		req = cachedUrlStream url
		req.pipe untar.stdin

		untar.stderr.on 'data', (data) ->
			console.log 'unpack:', data

		req.on 'error', (err) ->
			cache.invalidate url
			while done = isDownloading[url].pop()
				done err

		untar.on 'close', (code) ->
			console.log "took: " + (new Date - b)
			while done = isDownloading[url].pop()
				return done() if code is 0
				done "Failed to unpack #{url}. Exit code: #{code}"

