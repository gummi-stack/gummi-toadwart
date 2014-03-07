fs = require 'fs'
config = "/etc/toadwart/config.cson"

config = "./config.cson" unless fs.existsSync(config)

(require 'cson-config').load(config)

process.config.name = require('os').hostname()
config = process.config

express = require 'express'
util = require 'util'
network = require './lib/network'
lxc = require './lib/lxc/ops'
storage = require('./lib/storage/') config.images


# syslog.info 'find me in the logs'
# return


fn = util.inspect
util.inspect = (a, b, c) ->
	fn a, b, c, yes

util.log "Prepare network ...".green
network.init (err, dhcp) ->
	if err
		util.error "Network init crash"
		process.exit 1

	app = express()

	app.use (req, res, next) ->
		req.headers['content-type'] ?= "application/json; charset=utf-8"
		req.headers['accept'] ?= "application/json"
		req.headers.accept ?= "application/json"
		next()


	app.use app.router
	app.use express.errorHandler()

	lxc app, dhcp, storage

	app.listen config.port
	util.log "Toadwart \"#{config.name}\" id: \"#{config.id}\" serving on #{config.port}".green

