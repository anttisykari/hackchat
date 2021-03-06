# Utilities

log = -> console.log arguments...
s = -> JSON.stringify arguments...

# Remove any number of #'s from the beginning of the channel name.
sanitize = (channel) ->
	channel.replace /^#+/, ''

connected = false
socket = io.connect()

# Channel management

# Those that came from the hash on the first page load: /#foo,bar,zot
initialChannels = []

# List of all channels this socket is on. Listen/unlisten controls this.
channels = []

# List of all channels this user is on. Join/leave controls this.
allChannels = []

# Command history.
history = []
historyIdx = 0
newestCommand = ''

# Mirror the html elements of respective classes.
mynick = null
mychannel = null

updateChannels = ->
	location.hash = channels.join ','
	lis = ""
	for channel in channels
		lis += "<li>##{channel}</li>"
	$('.channels').html(lis)
	
# Add channel to list of current channels; if already there, do nothing
addChannel = (channel) ->
	if channel not in channels
		channels.push channel
		updateChannels()
		if channels.length > 1
			$('.ifchannel').show()
		# TODO update allChannels
		# allChannels.push ...

# Remove channel from list, return channel next to it
removeChannel = (channel) ->
	idx = channels.indexOf channel
	if idx != -1
		channels.splice idx, 1
	updateChannels()
	if channels.length <= 1
		$('.ifchannel').hide()
	if channels.length == 0
		return null
	else
		return channels[if idx == channels.length then idx - 1 else idx]
	# TODO update allChannels
	# allChannels.remove...

# TODO might be a nice idea to push the next channel in the place where current
# channel is.
setChannel = (next) ->
#	console.log "setChannel #{next}"
	mychannel = next

	if next
		addChannel next
		$('.mychannel').html('#' + next)
		if channels.length >= 2
			$('.ifchannel').show()
		$('.channels li').each (idx, elem) ->
			content = $(elem).html()
			
			$(elem)[if content == '#' + next then 'addClass' else 'removeClass'] 'current'
	else
		$('.mychannel').html('')
		$('.ifchannel').hide()

#	console.log "post setChannel, channels is #{channels}"

next = () ->
	if channels.length <= 1 || not mychannel
		return
	newChannel = channels[(channels.indexOf(mychannel) + 1) % channels.length]
	setChannel(newChannel)

prev = () ->
	if channels.length <= 1 || not mychannel
		return
	newChannel = channels[(channels.indexOf(mychannel) - 1 + channels.length) % channels.length]
	setChannel(newChannel)

escapeHtml = (s) ->
	s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
	.replace(/"/g, "&quot;") .replace(/'/g, "&#039;")

debug = false

emit = (what, msg) ->
	if debug
		show "Sent #{what.toUpperCase()}: #{JSON.stringify msg}"
	socket.emit what, msg

ping = ->
	emit 'ping', ts: new Date().getTime()

newNick = (newNick) ->
	emit 'nick', newNick: newNick

join = (channel, opts = {}) ->
	channel = sanitize channel
	opts.channel = channel
	# TODO maybe should specify silent: true 
	# if we are already on that channel, which we might know from allChannels.
	# But do we actually know it?
	console.log "join; ALLCHANNELS IS: "
	console.log allChannels
	emit 'join', opts

listen = (channel) ->
	channel = sanitize channel
	emit 'listen', channel: channel

unlisten = (channel) ->
	channel = sanitize channel
	emit 'unlisten', channel: channel

leave = (channel, message) ->
	if not channel
		show '*** Please specify channel.'
	else
		channel = sanitize channel
		emit 'leave', channel: channel, message: message || "leaving"

names = (channel) ->
	if not channel
		show '*** Please specify channel.'
	else
		channel = sanitize channel
		emit 'names', channel: channel

whois = (nick) ->
	if not nick
		show '*** Please specify nick.'
	emit 'whois', nick: nick

list = ->
	emit 'list'

reconnect = ->
	if connected
		show "*** Disconnecting."
		socket.disconnect()

	# Incredible hack to recover socket.io.
	uri = io.util.parseUri()
	uuri = null

	if window && window.location
		uri.protocol = uri.protocol || window.location.protocol.slice(0, -1)
		uri.host = uri.host || (if window.document then window.document.domain else window.location.hostname)
		uri.port = uri.port || window.location.port

	uuri = io.util.uniqueUri(uri)
		
	show "*** Reconnecting to #{uuri}."
	delete io.sockets[uuri]
	socket = io.connect()
	initSocket()

help = (help) ->
	show "*** Available commands:"
	show "*** /nick <nick> - change nick."
	show "*** /list - show channels"
	show "*** /say <message> - say on current channel."
	show "*** /join <channel> - join a channel. Alias: /j"
	show "*** /listen <channel> - listen to a channel."
	show "*** /unlisten <channel> - don't listen to a channel."
	show "*** /names [<channel>] - show who's on a channel"
	show "*** /next - next channel (shortcut: Ctrl-X)"
	show "*** /prev - previous channel"
	show "*** /whois [<nick>] - show info about a person"
	show "*** /leave [<channel>] [<message>] - leave a channel (current channel by default)"
#	show "*** /msg <nick> <message> - send private message to <nick>"
	show "*** /help - here we are. Alias: /h"
	show "*** /ping - ping the server."
	show "*** /set - set a variables."
	show "*** /reconnect - try to connect to the server if we're not connected."

say = (channel, msg) ->
	if not channel?
		show "*** You're not on a channel - try joining one. /list shows available channels."
	else
		channel = sanitize channel
		emit 'say', channel: channel, msg: msg

formatTime = (date) ->
	hours = String(date.getHours())
	mins = String(date.getMinutes())
	while hours.length < 2
		hours = '0' + hours
	while mins.length < 2
		mins = '0' + mins
	"#{hours}:#{mins}"

show = (msg, ts) ->
	showRaw escapeHtml(msg), ts

showRaw = (msg, ts) ->
	ts ?= new Date().getTime()
	date = new Date(ts)
	time = formatTime(date)

	$('.chat').append "<p><time datetime='#{date.toISOString()}'>#{time}</time> #{msg}</p>"
	# probably close enough
	$('.chat').scrollTop 1000000

isCommand = (cmd) ->
	cmd.match /^\//

parseCommand = (cmd) ->
	[command, args...] = cmd.split /\s+/
	if command == '/'
		{ command: 'say', args: cmd.replace(/^\/\s+/, '') }
	else
		{ command: command.replace(/^\//, ''), args: args }

up = ->
	command = $('#cmd').val()
	if historyIdx == history.length
		newestCommand = command
	if --historyIdx < 0
		historyIdx = 0
	if historyIdx == history.length
		$('#cmd').val(newestCommand)
	else
		$('#cmd').val(history[historyIdx])
	$('#cmd')[0].setSelectionRange(10000, 10000)

down = ->
	command = $('#cmd').val()
	if historyIdx == history.length
		newestCommand = command
	if ++historyIdx > history.length
		historyIdx = history.length
	if historyIdx == history.length
		$('#cmd').val(newestCommand)
	else
		$('#cmd').val(history[historyIdx])
	$('#cmd')[0].setSelectionRange(10000, 10000)

execute = (cmd) ->
	if cmd.match /^\s*$/
		return

	history.push cmd
	historyIdx = history.length
	newestCommand = ''

#	console.log "history: #{JSON.stringify history}"

	if isCommand cmd
		{ command, args } = parseCommand cmd
	else
		{ command, args } = { command: 'say', args: cmd }

	switch command
		when 'nick' then newNick args[0]
		when 'ping' then ping()
		when 'join', 'j' then join args[0]
		when 'listen' then listen args[0]
		when 'unlisten' then unlisten args[0]
		when 'names', 'n' then names (args[0] ? mychannel)
		when 'whois', 'w' then whois (args[0] ? mynick)
		when 'list' then list()
		when 'say', 's' then say mychannel, args
		when 'help', 'h' then help args
		when 'reconnect', 're', 'reco' then reconnect()
		when 'leave', 'le', 'part' then leave(args[0] ? mychannel, args[1..].join ' ')
		when 'next' then next()
		when 'prev' then prev()
		when 'raw' then emit args[0], JSON.parse(args[1..].join(' '))
		else show "*** I don't know that command: #{command}."

initSocket = () ->
	previousInfo = null

	wasDuplicate = (info) ->
		if JSON.stringify(previousInfo) == JSON.stringify(info)
			#console.log "### Ignoring duplicate info #{JSON.stringify info}"
			true
		else
			previousInfo = info
			false

	protocol =
		disconnect: ->
			show "*** Disconnected from server."
			connected = false

		connect: ->
			show "*** Connected to server."
			connected = true
			if debug
				ping()

		names: ({ channel, names }) ->
			names.sort()
			show "*** There are #{names.length} people on ##{channel}:"
			show "*** #{names.join ' '}"

		pong: (data) ->
			backThen = data.ts
			now = new Date().getTime()
			show "*** pong - roundtrip #{now - backThen} ms"

		channels: (data) ->
			channelNames = []
			for channel, idx in data.channels
				channelNames.push('#' + channel)
			if data.you
				allChannels = data.channels

				# If no channels on hash, and we get our channels,
				# listen to all of them
				if !initialChannels.length
					for channel in data.channels
						listen channel

				if data.channels.length
#					setChannel channels[0]
					show "*** You're on channels: #{channelNames.join ' '}"
				else
					show "*** You're not on any channels."
			else
				show "*** #{data.nick} is on channels: #{channelNames.join ' '}"

		listen: ({ nick, channel, you }) ->
			unless you
				show "*** TODO FIXME BROKEN IS THIS"
			setChannel channel

		nick: ({ oldNick, newNick, you }) ->
			info = { nick: { oldNick: oldNick, newNick: newNick } }
			if wasDuplicate(info)
				return

			if you
				show "*** You are now known as #{newNick}."
				mynick = newNick
				$('.mynick').html(newNick)
			else
				show "*** #{oldNick} is now known as #{newNick}."

		error: (data) ->
			show "*** Failed to reconnect. Please try again later."

		info: ({ msg }) ->
			show "[info] #{msg}"

		msg: ({ from, msg }) ->
			show "<#{from}> #{msg}"

		join: ({ nick, channel }) ->
			tellUser = true
			if nick == mynick
				# TODO should check 'you' instead? 
				setChannel(channel)
				if channel in channels
					tellUser = false
				else
					addChannel channel

			if tellUser
				show "*** #{nick} has joined channel ##{channel}."

		leave: ({ nick, channel, message }) ->
			show "*** #{nick} has left channel ##{channel} (#{message})."

			if nick == mynick
				nextChannel = removeChannel channel
				if mychannel == channel
					setChannel(nextChannel)

		say: ({ nick, channel, msg }) ->
			style = if channels.length <= 1 then 'display: none' else ''

			# TODO should control visi
			showRaw "&lt;#{escapeHtml nick}<span class='ifchannel' style='#{style}'>:##{escapeHtml channel}</span>&gt; #{escapeHtml msg}"

	for what, action of protocol
		do (what, action) ->
#			log "Listening to #{what} with #{action}"
			socket.on what, (data) ->
#				log "Got command #{what}"
				if debug
					if data?
						show "Got #{what.toUpperCase()}: #{s data}"
					else
						show "Got #{what.toUpperCase()}"
				action data

	

$ ->
	mynick = $('.mynick').html()

	initSocket()

	# Try very hard to keep the keyboard focus in #cmd
	focus = ->
		$('#cmd').focus()
	focus()

	clicks = 0
	timer = null

	$(window).click (e) ->
		clicks++
		if clicks == 1
			timer = setTimeout(->
				clicks = 0
				focus()
			,	300)
		else
			clearTimeout timer
			timer = setTimeout(->
				clicks = 0
			,	300)

	# Magic keys (plus focus)
	$(window).keypress (e) ->
		if e.target.id != 'cmd'
			$('#cmd').focus()
		# Ctrl-X
		if e.ctrlKey && e.keyCode == 24
			if e.shiftKey then prev() else next()
		# Ctrl-U
		if e.ctrlKey && e.keyCode == 21
			$('#cmd').val('')

	# Command line logic
	$('#cmd').keydown (event) ->
		if event.keyCode == 13
			cmd = $(event.target).val()
			execute(cmd)
			$(event.target).val('')
		if event.keyCode == 38
			up()
			event.preventDefault()
		if event.keyCode == 40
			down()
			event.preventDefault()

	$('#cmd').focus ->
		$('.input').addClass('focus')
	$('#cmd').blur ->
		$('.input').removeClass('focus')

	# Clicking on channel in mychannels changes to it
	$('.channels li').live 'click', (ev) ->
		channel = $(ev.target).html()
		setChannel sanitize channel

	# Silly time hover thing - remove me and replace with a better one
	$('time').live 'click', (ev) ->
		show "*** That's #{new Date($(ev.target).attr('datetime'))}."

	channelsInHash = (window.location.hash.replace /^#/, '').trim().split ','
	for c in channelsInHash	
		initialChannels.push c if c

	# TODO handling of these if no channels to listen
	console.log "initials #{JSON.stringify initialChannels}"
	for c in initialChannels
		join c, silent: true

	windowHeight = $(window).height()

	$(window).resize ->
		newHeight = $(window).height()
		if newHeight != windowHeight
			windowHeight = newHeight
			doLayout()

	doLayout = () ->
		magic = 76
		$('.chat').css('height', windowHeight - magic)
		$('body').css('height', windowHeight)

	doLayout()

