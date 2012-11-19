exec = require("child_process").exec
fs = require 'fs'
util = require 'util'

class Dhcp

	###
		@param config {
			addresses: '10.1.69.50-10.1.69.99',
			everything_other: "will be forwarded"
		}
	###
	constructor: (@config) ->
		addresses = @config.addresses
		delete @config.addresses

		# rozebrani a vycisteni rozsahu adres
		[min, max] = addresses.replace(/\s/g, '').split '-'
		parsedMin = min.split('.').map (value) -> parseInt value
		parsedMax = max.split('.').map (value) -> parseInt value
		parsedMin[3] = 1 if parsedMin[3] is 0
		parsedMax[3] = 1 if parsedMax[3] is 0
		min = parsedMin.join('.')
		max = parsedMax.join('.')

		throw new Error 'Invalid IP range' unless @_checkRange parsedMin, parsedMax

		ip = min
		parsed = parsedMin

		# nacist pridelene adresy ze souboru
		backup = @_readBackup()

		@_pool = {}
		@_leased = {}

		@_pool[ip] = null
		@_lease ip if backup.indexOf(ip) > -1
		

		while ip isnt max
			pos = 3
			# na dalsi adresu
			while ++parsed[pos] > 255
				parsed[pos] = if pos is 3 then 1 else 0
				pos--
			ip = parsed.join('.')
			@_pool[ip] = null
			@_lease ip if backup.indexOf(ip) > -1
		
		

	###
		@return {
			ip: "10.1.69.50",
			everything_other: "from config"
		}
	###
	get: () =>
		for ip of @_pool
			if @_pool[ip] is null
				@_lease ip
				res = ip: ip
				res[key] = @config[key] for key of @config
				return res
				
		throw new Error 'IP pool is empty'


	_checkRange: (min, max) =>
		for value, index in min
			maxValue = max[index]
			throw new Error 'Invalid IP address' if value > 255 or maxValue > 255
			return false if value > maxValue
			return true if value < maxValue
		return true


	_lease: (ip) =>
		@_pool[ip] = new Date

		check = () =>
			exec "ping -c 1 -w 5 #{ip}", (error, stdout, stderr) =>
				# pokud zarizeni neodpovida, skonci to chybou
				@_cancel ip if error

		@_leased[ip] = setInterval check, 1000 * 5
		check()
		@_backup()


	_cancel: (ip) =>
		clearInterval @_leased[ip]
		delete @_leased[ip]
		@_pool[ip] = null
		@_backup()


	_backup: () =>
		backup = JSON.stringify Object.keys @_leased
		fs.writeFileSync __dirname + "/dhcp.tmp", backup


	_readBackup: () =>
		try
			saved = fs.readFileSync __dirname + "/dhcp.tmp"
			JSON.parse saved
		catch e
			[]


module.exports = Dhcp
