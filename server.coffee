#!/usr/bin/env coffee

http = require 'http'

server = http.createServer (req, res) ->
  res.writeHead(200, {'Content-Type': 'text/plain'})
  res.end('Hello World\n')

server.listen 8000

console.log 'Server running at http://0.0.0.0:8000/'
