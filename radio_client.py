# TODO:
# use steam ids not names
# youtube shorts links dont work
# delete tts mp3s after finished

import time, os, sys, queue, random, datetime, socket, subprocess, traceback, json, pafy, urllib
from threading import Thread, Lock
from gtts import gTTS

#import youtube_dl
import yt_dlp as youtube_dl

sven_root = '../../../..'
csound_path = os.path.join(sven_root, 'svencoop_downloads/sound/twlz')
tts_enabled = True
g_media_players = []
tts_id = 0
g_tts_players = {}
command_queue = queue.Queue() # commands from the server
send_queue = queue.Queue() # messages for the server
lock_queue = queue.Queue()
command_prefix = '~'
cached_video_urls = {} # maps a youtube link ton audio link that VLC can stream

#command_queue.put('w00tguy\\en\\100\\https://www.youtube.com/watch?v=zZdVwTjUtjg')
#command_queue.put('w00tguy\\en\\80\\~test test test test test test test test test test test test test test')
#command_queue.put('w00tguy\\en\\80\\https://youtu.be/-zEJEdbZUP8')
#command_queue.put('w00tguy\\en\\80\\~testaroni')

hostname = '192.168.254.158' # woop pc
#hostname = '107.191.105.136' # VPS
hostport = 1337
our_addr = (hostname, hostport)

reconnect_tcp = False
g_pause_packets = False

server_timeout = 5 # time in seconds to wait for server heartbeat before disconnecting
resend_packets = 0 # send packets X extra times to help prevent lost packets while keeping latency down
g_pipe_count = 16 # should be in sync with steam_voice program
g_reserved_pipes = set([]) # pipes that are probably about to be written to by ffmpeg
pipe_mutex = Lock()

g_valid_langs = {
	'af': {'tld': 'com', 'code': 'af', 'name': 'African'},
	'afs': {'tld': 'co.za', 'code': 'en', 'name': 'South African'},
	'ar': {'tld': 'com', 'code': 'ar', 'name': 'arabic'},
	'au': {'tld': 'com.au', 'code': 'en', 'name': 'Austrailian'},
	'bg': {'tld': 'com', 'code': 'bg', 'name': 'bulgarian'},
	'bn': {'tld': 'com', 'code': 'bn', 'name': 'Bengali'},
	'br': {'tld': 'com.br', 'code': 'pt', 'name': 'brazilian'},
	'bs': {'tld': 'com', 'code': 'bs', 'name': 'Bosnian'},
	'ca': {'tld': 'ca', 'code': 'en', 'name': 'Canadian'},
	'cn': {'tld': 'com', 'code': 'zh-CN', 'name': 'chinese'},
	'cs': {'tld': 'com', 'code': 'cs', 'name': 'Czech'},
	'ct': {'tld': 'com', 'code': 'ca', 'name': 'Catalan'},
	'cy': {'tld': 'com', 'code': 'cy', 'name': 'Welsh'},
	'da': {'tld': 'com', 'code': 'da', 'name': 'Danish'},
	'de': {'tld': 'com', 'code': 'de', 'name': 'German'},
	'el': {'tld': 'com', 'code': 'el', 'name': 'Greek'},
	'en': {'tld': 'com', 'code': 'en', 'name': 'american'},
	'eo': {'tld': 'com', 'code': 'eo', 'name': 'Esperanto'},
	'es': {'tld': 'es', 'code': 'es', 'name': 'spanish'},
	'et': {'tld': 'com', 'code': 'et', 'name': 'Estonian'},
	'fc': {'tld': 'ca', 'code': 'fr', 'name': 'french canadian'},
	'fi': {'tld': 'com', 'code': 'fi', 'name': 'Finnish'},
	'fr': {'tld': 'fr', 'code': 'fr', 'name': 'french'},
	'gu': {'tld': 'com', 'code': 'gu', 'name': 'Gujarati'},
	'hi': {'tld': 'com', 'code': 'hi', 'name': 'Hindi'},
	'hr': {'tld': 'com', 'code': 'hr', 'name': 'Croatian'},
	'hu': {'tld': 'com', 'code': 'hu', 'name': 'Hungarian'},
	'hy': {'tld': 'com', 'code': 'hy', 'name': 'Armenian'},
	'is': {'tld': 'com', 'code': 'is', 'name': 'Icelandic'},
	'id': {'tld': 'com', 'code': 'id', 'name': 'Indonesian'},
	'in': {'tld': 'co.in', 'code': 'en', 'name': 'Indian'},
	'ir': {'tld': 'ie', 'code': 'en', 'name': 'Irish'},
	'it': {'tld': 'com', 'code': 'it', 'name': 'Italian'},
	'ja': {'tld': 'com', 'code': 'ja', 'name': 'Japanese'},
	'jw': {'tld': 'com', 'code': 'jw', 'name': 'Javanese'},
	'km': {'tld': 'com', 'code': 'km', 'name': 'Khmer'},
	'kn': {'tld': 'com', 'code': 'kn', 'name': 'Kannada'},
	'ko': {'tld': 'com', 'code': 'ko', 'name': 'Korean'},
	'la': {'tld': 'com', 'code': 'la', 'name': 'Latin'},
	'lv': {'tld': 'com', 'code': 'lv', 'name': 'Latvian'},
	'ma': {'tld': 'com', 'code': 'es', 'name': 'Mexican American'},
	'mk': {'tld': 'com', 'code': 'mk', 'name': 'Macedonian'},
	'mr': {'tld': 'com', 'code': 'mr', 'name': 'Marathi'},
	'mx': {'tld': 'com.mx', 'code': 'es', 'name': 'Mexican'},
	'my': {'tld': 'com', 'code': 'my', 'name': 'Myanmar (Burmese)'},
	'ne': {'tld': 'com', 'code': 'ne', 'name': 'Nepali'},
	'nl': {'tld': 'com', 'code': 'nl', 'name': 'Dutch'},
	'no': {'tld': 'com', 'code': 'no', 'name': 'Norwegian'},
	'pl': {'tld': 'com', 'code': 'pl', 'name': 'Polish'},
	'pt': {'tld': 'pt', 'code': 'pt', 'name': 'portuguese'},
	'ro': {'tld': 'com', 'code': 'ro', 'name': 'Romanian'},
	'ru': {'tld': 'com', 'code': 'ru', 'name': 'Russian'},
	'si': {'tld': 'com', 'code': 'si', 'name': 'Sinhala'},
	'sk': {'tld': 'com', 'code': 'sk', 'name': 'Slovak'},
	'sq': {'tld': 'com', 'code': 'sq', 'name': 'Albanian'},
	'sr': {'tld': 'com', 'code': 'sr', 'name': 'Serbian'},
	'su': {'tld': 'com', 'code': 'su', 'name': 'Sundanese'},
	'sv': {'tld': 'com', 'code': 'sv', 'name': 'Swedish'},
	'sw': {'tld': 'com', 'code': 'sw', 'name': 'Swahili'},
	'ta': {'tld': 'com', 'code': 'ta', 'name': 'Tamil'},
	'te': {'tld': 'com', 'code': 'te', 'name': 'Telugu'},
	'th': {'tld': 'com', 'code': 'th', 'name': 'Thai'},
	'tl': {'tld': 'com', 'code': 'tl', 'name': 'Filipino'},
	'tr': {'tld': 'com', 'code': 'tr', 'name': 'Turkish'},
	'tw': {'tld': 'com', 'code': 'zh-TW', 'name': 'taiwanese'},
	'ek': {'tld': 'co.uk', 'code': 'en', 'name': 'british'},
	'uk': {'tld': 'com', 'code': 'uk', 'name': 'Ukrainian'},
	'ur': {'tld': 'com', 'code': 'ur', 'name': 'Urdu'},
	'vi': {'tld': 'com', 'code': 'vi', 'name': 'Vietnamese'}
}

def format_time(seconds):
	hours = int(seconds / (60*60))
	
	if hours > 0:
		remainder = int(seconds - hours*60*60)
		return "%dh %dm" % (hours, int(remainder / 60))
	else:
		minutes = int(seconds / 60)
		if minutes > 0:
			return "%dm %ds" % (minutes, int(seconds % 60))
		else:
			return "%ds" % int(seconds)

def get_free_stream_pipe():
	global g_media_players
	global g_pipe_count
	global g_reserved_pipes
	
	pipes = set([])
	
	for x in range(0, g_pipe_count):
		pipes.add('MicBotPipe%s' % x)
	
	for idx, player in enumerate(g_media_players):
		if player['player'].poll() is None:
			pipes.remove(player['pipe'])
			
	for x in g_reserved_pipes:
		pipes.remove(x)
	
	if len(pipes):
		print("%s pipes available" % len(pipes))
		return list(pipes)[0]
	
	return None

def get_youtube_info(url, channel, songId):
	global cached_video_urls
	
	try:
		if url not in cached_video_urls:
			print("Fetch best audio " + url)
			cached_video_urls[url] = load_info_from_url(url)
		else:
			print("Use cached url " + url)
			
		playurl = cached_video_urls[url]['url']
		title = cached_video_urls[url]['title']
		length = cached_video_urls[url]['length']
			
		send_queue.put("info:%s:%s:%s:%s" % (channel, songId, length, title))
	except Exception as e:
		print(e)
		send_queue.put("~Failed load video info for: " + url)

def load_info_from_url(url):
	if ('youtube.com' in url or 'youtu.be' in url) and '/shorts/' not in url:
		print("Using pafy for normal youtube link")
		# don't know why but seems like the urls pafy picks don't have lots of failures lilke when using ytdl directly
		video = pafy.new(url)
		return {'url': video.getbestaudio().url, 'title': video.title, 'length': video.length}

	with youtube_dl.YoutubeDL() as ydl:
		ydl_info = ydl.extract_info(url, download=False)
		
		print(json.dumps(ydl_info, sort_keys=True, indent=4))
		
		title = ydl_info['title']
		length = ydl_info['duration']
		audio_streams = [i for i in ydl_info['formats'] if i.get('acodec', 'none') != 'none' or i.get('vcodec', 'none') == 'none']
		audio_only_streams = [i for i in audio_streams if i.get('vcodec', 'none') == 'none']
		
		best_stream = None
		if len(audio_only_streams):
			for stream in audio_only_streams:
				if 'manifest_url' in stream or stream['ext'] == 'mhtml':
					continue # ffmpeg can't play these
				best_stream = stream
				break
		else:
			lowest_rez = 99999999
			for stream in audio_streams:
				if stream['width'] is None:
					continue
				print(json.dumps(stream, sort_keys=True, indent=4))
				rez = stream['width']*stream['height']
				if rez < lowest_rez:
					lowest_rez = rez
					best_stream = stream
		
		if type(title) == list:
			title = title[-1]
		
		print(json.dumps(best_stream, sort_keys=True, indent=4))
		return {'title': title, 'length': length, 'url': best_stream['url']}

def playtube_async(url, offset, asker, channelId, songId):
	global tts_id
	global g_media_players
	global cached_video_urls
	global send_queue
	global g_pipe_count
	global g_reserved_pipes
	
	#pipe_mutex.acquire()
	pipeName = get_free_stream_pipe()
	if not pipeName:
		send_queue.put("Server unable to stream more than %d videos at once." % g_pipe_count)
		send_queue.put("fail:%s:%s" % (channelId, songId))
		return
	g_reserved_pipes.add(pipeName)
	#pipe_mutex.release()
	
	try:		
		if url not in cached_video_urls:
			print("Fetch best audio " + url)
			cached_video_urls[url] = load_info_from_url(url)
		else:
			print("Use cached url " + url)
			
		playurl = cached_video_urls[url]['url']
		title = cached_video_urls[url]['title']
		length = cached_video_urls[url]['length']
		
		pipePrefix = '\\\\.\\pipe\\' if os.name == 'nt' else ''		
		pipePath = '%s%s' % (pipePrefix, pipeName)
		print("ffmpeg > %s" % pipeName)
		
		#if not os.name == 'nt':
		#	playurl = "'" + playurl + "'"
		safe_url = playurl.replace(" ", "%20").replace("'", '%27')
		
		loudnorm_filter = '-af loudnorm=I=-22:LRA=11:TP=-1.5' # uses too much memory
		cmd = 'ffmpeg -hide_banner -loglevel error -y -ss %s -i %s -f s16le -ar 12000 -ac 1 -' % (offset, safe_url)
		print(cmd)
		pipefile = open(pipePath, 'w')
		ffmpeg = subprocess.Popen(cmd.split(' '), stdout=pipefile)
		steam_voice.stdin.write("assign %s %d\n" % (pipeName, channelId))
		steam_voice.stdin.write("notify %s\n" % pipeName)
		
		g_media_players.append({
			'player': ffmpeg,
			'pipe': pipeName,
			'message_sent': False,
			'title': title,
			'asker': asker,
			'url': url,
			'length': length,
			'offset': offset,
			'channelId': channelId,
			'songId': songId
		})
		print("Play offset %d: " % offset)
	except Exception as e:
		traceback.print_exc()
		
		err_string = str(e).replace('\n','. ')
		send_queue.put("fail:%s:%s:%s" % (channelId, songId, err_string))
		
		#t = Thread(target = play_tts, args =('\\radio_client\\', err_string, tts_id, 'en', 1, False, ))
		#t.daemon = True
		#t.start()
		#tts_id += 1
		
	#pipe_mutex.acquire()
	g_reserved_pipes.remove(pipeName)
	#pipe_mutex.release()

def play_tts(speaker, text, id, lang, pitch, is_hidden):
	global steam_voice
	
	# Language in which you want to convert
	language = g_valid_langs[lang]['code']
	tld = g_valid_langs[lang]['tld']
	
	# Passing the text and language to the engine, 
	# here we have marked slow=False. Which tells 
	# the module that the converted audio should 
	# have a high speed
	print("Translating %d" % id)
	myobj = gTTS(text=text, tld=tld, lang=language, slow=False)
	 
	# Saving the converted audio in a mp3 file named
	# welcome
	fname = 'tts/tts%d' % id + '.mp3'
	try:
		myobj.save(fname)
	except Exception as e:
		print(e)
		return
		
	totalCaps = sum(1 for c in text if c.isupper())
	totalLower = sum(1 for c in text if c.islower())
	volume = 1000 if totalCaps > totalLower else 2
	
	# stop their last speech, if any
	if speaker in g_tts_players:
		steam_voice.stdin.write("stop " + g_tts_players[speaker] + "\n")
	
	steam_voice.stdin.write("play %s %.2f %.2f\n" % (fname, volume, pitch))
	g_tts_players[speaker] = fname
	 
	#print("Played %d" % id)
	
	#if is_hidden:
	#	send_queue.put("~[TTS] " + text)

def command_loop():
	global our_addr
	global command_queue
	global server_timeout
	global send_queue
	
	while True:
		try:
			tcp_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
			tcp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
			tcp_socket.bind(our_addr)
			tcp_socket.listen(1)
			tcp_socket.settimeout(2)
			data_stream = ''
		
			print("Waiting for command socket connection")
			connection, client = tcp_socket.accept()
			last_tcp_heartbeat = datetime.datetime.now()
			last_send_heartbeat = datetime.datetime.now()
			connection.settimeout(0.05)
		
			print("Command socket connected")
			# Receive and print data 32 bytes at a time, as long as the client is sending something
			while True:
				try:
					data = connection.recv(32)
				except Exception as e:					
					time_since_last_heartbeat = (datetime.datetime.now() - last_tcp_heartbeat).total_seconds()					
					if time_since_last_heartbeat > server_timeout:
						print("TCP connection appears broken. Restarting.")
						connection.close()
						break
						
					time_since_last_send_heartbeat = (datetime.datetime.now() - last_send_heartbeat).total_seconds()
					if time_since_last_send_heartbeat >= 2.0:
						last_send_heartbeat = datetime.datetime.now()
						connection.sendall(b'\n') # let the server know we're still alive
						
					if not send_queue.empty():
						msg = send_queue.get() + '\n'
						print(msg)
						connection.sendall(msg.encode())
						
					continue
				
				data_stream += data.decode('utf-8', errors='ignore')
				#print("Got data %s" % data.decode())
				last_tcp_heartbeat = datetime.datetime.now()
				
				if '\n' in data_stream:
					command = data_stream[:data_stream.find('\n')]
					data_stream = data_stream[data_stream.find('\n')+1:]
					command_queue.put(command)
	 
		except Exception as e:
			traceback.print_exc()
			

def transmit_voice():
	global server_timeout
	global resend_packets
	global steam_voice
	global send_queue
	global g_media_players
	global g_pause_packets
	
	udp_socket = socket.socket(family=socket.AF_INET, type=socket.SOCK_DGRAM)
	udp_socket.bind(our_addr)
	udp_socket.settimeout(0)
	
	server_addr = None

	last_heartbeat = datetime.datetime.now()
	packetId = 0

	sent_packets = []
	sent_packets_first_id = 0 # packet id of the first packet in sent_packets
	
	for line in iter(steam_voice.stdout.readline, ''):
		line = line.strip()
		
		if not line:
			time.sleep(0.1)
			print("DELAY STDOUT")
			
		if line.startswith('notify'):
			pipeName = line.split(' ')[1]
			for idx, player in enumerate(g_media_players):
				if player['pipe'] == pipeName:
					player['message_sent'] = True
					send_queue.put("play:%s:%s:%s:%s:%s:%s" % (player['channelId'], player['songId'], packetId, player['offset'], player['length'], player['title']))
					player['start_time'] = time.time()
					break
			continue

		if g_pause_packets:
			continue

		packet = packetId.to_bytes(2, 'big')
		for idx, stream in enumerate(line.split(":")):
			numBytes = int(len(stream)/2)
			packet += numBytes.to_bytes(2, 'big') + bytes.fromhex(stream)
			#print("STREAM %d (%d): %s" % (idx, len(stream), stream))
			
		#print("Send %d (%d bytes)" % (packetId, len(packet)))
		
		if server_addr:
			udp_socket.sendto(packet, server_addr)
			
			if len(sent_packets) > resend_packets:
				for x in range(0, resend_packets):
					udp_socket.sendto(b'resent' + sent_packets[-x][1], server_addr)
				
			sent_packets.append((packetId, packet))
			#print("Send %d (%d bytes)" % (packetId, len(packet)))
			
			packetId = (packetId + 1) % 65536
			#packetId = (packetId + 1) % 200
			
			if (len(sent_packets) > 128):
				sent_packets = sent_packets[(len(sent_packets) - 128):]
		else:
			print("Waiting for heartbeat on %s:%d" % (hostname, hostport))
			time.sleep(1)
		
		# handle some requests from the server
		for x in range(0, 4):
			try:
				udp_packet = udp_socket.recvfrom(1024)
				if udp_packet[0] == b'dere':
					if not server_addr or udp_packet[1][0] != server_addr[0] or udp_packet[1][1] != server_addr[1]:
						print("Server address changed! Must have restarted.")
						server_addr = udp_packet[1]
				else:
					want_id = int.from_bytes(udp_packet[0], "big")
					
					found = False
					for packet in sent_packets:
						if packet[0] == want_id:
							udp_socket.sendto(b'resent' + packet[1], server_addr)
							found = True
							#print("Resending %d" % want_id)
							break
					if not found:
						print("Server wanted %d, which is not in sent history" % want_id)
					
				last_heartbeat = datetime.datetime.now()
			except Exception as e:
				break
			
		time_since_last_heartbeat = (datetime.datetime.now() - last_heartbeat).total_seconds()
		
		if (time_since_last_heartbeat > server_timeout and server_addr):
			print("Server isn't there anymore! Probably!!! Wait for reconnect....")
			server_addr = None

def steam_voice_stderr():
	global steam_voice
	
	for line in iter(steam_voice.stderr.readline, ''):
		line = line.strip()
		if not line:
			continue
		print("[steam_voice] %s" % line)

process_name = 'steam_voice.exe' if os.name == 'nt' else 'steam_voice'
steam_voice = subprocess.Popen(os.path.join('lib', process_name),
							   bufsize=1, universal_newlines=True,
							   stdout=subprocess.PIPE, stdin=subprocess.PIPE, stderr=subprocess.PIPE)

t = Thread(target = command_loop, args =( ))
t.daemon = True
t.start()

t = Thread(target = steam_voice_stderr, args =( ))
t.daemon = True
t.start()

t = Thread(target = transmit_voice, args =( ))
t.daemon = True
t.start()

while True:
	wasplaying = len(g_media_players) > 0
	
	for idx, player in enumerate(g_media_players):
		isRunning = player['player'].poll() is None
		if not isRunning:
			g_media_players.pop(idx)
			if 'was_stopped' in player:
				continue
			
			if not player['message_sent']:
				send_queue.put("fail:%s:%s" % (player['channelId'], player['songId']))
				send_queue.put("Failed to play a video from %s" % player['asker'])
				if player['url'] in cached_video_urls:
					del cached_video_urls[player['url']]
				continue
			
			playTime = time.time() - player['start_time']
			expectedPlayTime = player['length'] - player['offset']
			if playTime < expectedPlayTime - 10:
				send_queue.put("~Video playback failed at %s. Attempting to resume." % format_time(playTime + player['offset']))
				t = Thread(target = playtube_async, args =(player['url'], player['offset'] + int(playTime + 1.5), player['asker'], player['channelId'], player['songId'], ))
				t.daemon = True
				if player['url'] in cached_video_urls:
					del cached_video_urls[player['url']]
				t.start()
				continue
			
			print("Finished playing video (%.1f left)" % (expectedPlayTime - playTime))
			break
	
	line = None
	try:
		line = command_queue.get(True, 0.05)
	except Exception as e:
		pass
	
	if not line:
		continue

	print(line.strip())
	
	name = line[:line.find("\\")]
	line = line[line.find("\\")+1:]
	lang = line[:line.find("\\")]
	line = line[line.find("\\")+1:]
	pitch = float(line[:line.find("\\")]) / 100
	line = line[line.find("\\")+1:]

	#print(name + ": " + line.strip())
	
	if line.startswith('https://') or line.startswith('http://'):				
		args = line.split()
		offset = 0
		channelId = 0
		songId = 0
		try:
			if len(args) >= 3:
				channelId = int(args[1])
				songId = int(args[2])
				timecode = args[3]
				if ':' in timecode:
					minutes = timecode[:timecode.find(':')]
					seconds = timecode[timecode.find(':')+1:]
					offset = int(minutes)*60 + int(seconds)
				else:
					offset = int(timecode)
		except Exception as e:
			print(e)
	
		t = Thread(target = playtube_async, args =(args[0], offset, name, channelId, songId, ))
		t.daemon = True
		t.start()
		continue
	
	had_prefix = line.startswith(command_prefix)
	if had_prefix:
		line = line[1:]
	
	if line.startswith('.info'):
		channel = int(line.split()[1])
		songId = int(line.split()[2])
		url = line.split()[3]
		
		t = Thread(target = get_youtube_info, args =(url, channel, songId, ))
		t.daemon = True
		t.start()
		
		continue
		
	if line.startswith('.encoder'):
		message = line[len('.encoder')+1:]
		steam_voice.stdin.write(message + "\n")
		continue
		
	if line.startswith('.pause_packets'):
		g_pause_packets = True
		continue
		
	if line.startswith('.resume_packets'):
		g_pause_packets = False
		continue
		
	if line.startswith('.clear_cache'):
		cached_video_urls = {}
		continue
	
	if line.startswith('.stopid'):
		songIds = []
		for part in line.split()[1:]:
			songIds.append(int(part))
		
		for idx, player in enumerate(g_media_players):
			if player['songId'] in songIds:
				player['player'].terminate()
				player['was_stopped'] = True
				steam_voice.stdin.write('stop ' + player['pipe'] + "\n")
				found_vid = True
				print("Song %d was stopped" % player['songId'])

		continue
		
	if line.startswith('.mstop'):
		args = line.split()
		arg = args[1] if len(args) > 1 else ""
			
		if arg == "" or arg == 'speak':
			for key, fname in g_tts_players.items():
				steam_voice.stdin.write('stop ' + fname + "\n")
			g_tts_players = {}
		
	
		t = Thread(target = play_tts, args =(name, 'stop ' + arg, tts_id, lang, pitch, False, ))
		t.daemon = True
		t.start()
		tts_id += 1
		continue
	
	if tts_enabled:		
		t = Thread(target = play_tts, args =(name, line, tts_id, lang, pitch, had_prefix, ))
		t.start()
		tts_id += 1
		
	
	
