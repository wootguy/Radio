import socket, sys, time, datetime, os, queue
from threading import Thread

# "client" that generates the voice data
#hostname = '47.157.183.178' # twlz
#hostname = '192.168.254.158' # woop pc
#hostname = '192.168.254.106' # Windows VM
#hostname = '192.168.254.110' # Linux VM
hostname = '107.191.105.136' # VPS
hostport = 1337
client_address = (hostname, hostport)

voice_data_file = '../../../../svencoop/scripts/plugins/store/_fromvoice.txt'
voice_cmd_file = '../../../../svencoop/scripts/plugins/store/_tovoice.txt'

# higher than 16 and plugin might send packets so fast that the stream cuts out
# special throttling logic is needed for higher buffer sizes
buffer_max = 4
buffered_buffers = 3 # number of buffers to hold onto before sending to the plugin. Higher = fewer lost packets

last_file_write = datetime.datetime.now()
last_heartbeat = datetime.datetime.now()
min_time_between_writes = 0.1 # give the plugin time to load the file. Keep value in sync with plugin
time_between_heartbeats = 1 # time between packets to the client, letting it know the server is still listening
response_queue = queue.Queue()
last_tcp_heartbeat = datetime.datetime.now()
last_client_heartbeat = datetime.datetime.now()

fsizeHackIdx = 0
g_packet_streams = 0 # set automatically on receiving data

def tcp_heartbeat(socket):
	global last_tcp_heartbeat
	
	time_since_last_heartbeat = (datetime.datetime.now() - last_tcp_heartbeat).total_seconds()
	
	if time_since_last_heartbeat > 2.0:
		#print("send heartbeat")
		last_tcp_heartbeat = datetime.datetime.now()
		socket.sendall(b'\n')
		
def tcp_listen(socket, response_data):
	global last_client_heartbeat
	global response_queue
	
	try:
		data = socket.recv(32).decode()
		if data:
			last_client_heartbeat = datetime.datetime.now()
			response_data += data
			
			if '\n' in response_data:
				message = response_data[:response_data.find('\n')]
				response_data = response_data[response_data.find('\n')+1:]
				if message:
					print(message)
					response_queue.put(message)
			#print("got: %s" % data)
		else:
			time_since_last_client_heartbeat = (datetime.datetime.now() - last_client_heartbeat).total_seconds()
			if time_since_last_client_heartbeat > 2.0:
				print("Client appears disconnected. Restarting command socket loop.")
				return None
	except Exception as e:
		#print(e)
		pass
		
	return response_data

def follow(socket, thefile):
	'''generator function that yields new lines in a file
	   also threw in some tcp heartbeat and response message logic because yolo
	'''
	# seek the end of the file
	thefile.seek(0, os.SEEK_END)
	
	response_data = ''
	
	# start infinite loop
	while True:
		# read last line of file
		line = thefile.readline()        # sleep if file hasn't been updated
		if not line:
			time.sleep(0.1)
			
			tcp_heartbeat(socket)
			
			response_data = tcp_listen(socket, response_data)
			if response_data is None:
				break
				
			continue

		yield line


def command_loop():
	global client_address
	global voice_cmd_file
	
	while True:
		try:
			print("Creating command socket")
			# Create a connection to the server application on port 81
			tcp_socket = socket.create_connection(client_address)
			tcp_socket.settimeout(1)
			print("Command socket connected")

			logfile = open(voice_cmd_file, encoding='utf8', errors='ignore')
			loglines = follow(tcp_socket, logfile)

			for line in loglines:
				print("Send command: " + line.strip())
				tcp_socket.sendall(line.encode())
				
			tcp_socket.close()
		except Exception as e:
			print(e)

# Tell the voice client that we're still listening.
# This also initiates a connection without having to open a port on the server running this script.
# UDP traffic is allowed in once the server tries to communicate on the port.
def heartbeat(socket):
	global time_since_last_heartbeat
	global last_heartbeat
	global client_address
	
	time_since_last_heartbeat = (datetime.datetime.now() - last_heartbeat).total_seconds()
		
	if time_since_last_heartbeat > time_between_heartbeats:
		socket.sendto(b'dere', client_address)
		last_heartbeat = datetime.datetime.now()
		#print("heartbeat %s:%d" % client_address)

def send_packets_to_plugin(socket, all_packets, force_send):
	global last_file_write
	global min_time_between_writes
	global buffered_buffers
	global buffer_max
	global voice_data_file
	global client_address
	global response_queue
	global fsizeHackIdx
	global g_packet_streams
	
	if len(all_packets) == 0:
		return all_packets
	
	if not force_send:
		time_since_last_write = (datetime.datetime.now() - last_file_write).total_seconds()
		if len(all_packets) < buffer_max*buffered_buffers or time_since_last_write < min_time_between_writes:
			return all_packets
	
	last_file_write = datetime.datetime.now()
	
	with open(voice_data_file, "w") as f:
		lost = 0
		for packet in all_packets[:buffer_max]:
			if type(packet) is int:
				lost += 1
				f.write('%0.4x%s\n' % (packet, '00' * g_packet_streams))
			else:
				#print("Wrote %d" % len(packet))
				f.write(packet)
				
		if not response_queue.empty():
			f.write('m' + response_queue.get() + '\n')
		
		# random data so file size always changes (plugin compares size to check if there's new data)
		f.write('z'*fsizeHackIdx + '\n')
		fsizeHackIdx = (fsizeHackIdx + 1) % 8
		
		all_packets = all_packets[buffer_max:]
		
		still_missing = 0
		for idx, packet in enumerate(all_packets):
			if type(packet) is int:
				socket.sendto(packet.to_bytes(2, 'big'), client_address)
				still_missing += 1
				#print("  Asked to resend %d" % (packet))
				
		print("Wrote %d packets (%d lost, %d buffered, %d requested)" % (buffer_max, lost, len(all_packets), still_missing))
	
	return all_packets

def receive_voice_data():
	global client_address
	global response_queue
	global buffered_buffers
	global buffer_max
	global g_packet_streams

	all_packets = []
	expectedPacketId = -1
	last_packet_time = datetime.datetime.now()
	is_connected = False

	udp_socket = socket.socket(family=socket.AF_INET, type=socket.SOCK_DGRAM)
	udp_socket.settimeout(1)
	print("Contacting voice data client %s:%d" % (hostname, hostport))

	while True:
		heartbeat(udp_socket)
		
		time_since_last_packet = (datetime.datetime.now() - last_packet_time).total_seconds()
		if time_since_last_packet > 3:
			expectedPacketId = -1
			if is_connected:
				response_queue.put("Micbot is now offline.")
			is_connected = False
			all_packets = send_packets_to_plugin(udp_socket, all_packets, True)
		
		try:
			udp_packet = udp_socket.recvfrom(1024)
		except socket.timeout:
			continue
		except Exception as e:
			print(e)
			continue
		
		last_packet_time = datetime.datetime.now()
		if not is_connected:
			response_queue.put("Micbot is now online. Say .mhelp for commands.")
		is_connected = True
		
		data = udp_packet[0]
		
		is_resent = data[:6] == b'resent'
		if is_resent:
			data = data[6:]
			
		packetId = int.from_bytes(data[:2], "big")
		data = data[2:]
		
		hexString = '%04x' % packetId
		
		g_packet_streams = 0
		while len(data) > 0:
			streamSize = int.from_bytes(data[:2], "big")
			data = data[2:]
			hexString += ':' + ''.join(format(x, '02x') for x in data[:streamSize])
			data = data[streamSize:]
			g_packet_streams += 1
			
		hexString += '\n'
		
		#print("Got %d streams" % totalStreams)
		#print("Got %d (%d bytes)" % (packetId, len(data)))
		
		if is_resent:
			# got a resent packet, which we asked for earlier
			recovered = False
			for idx, packet in enumerate(all_packets):
				if type(packet) is int and packet == packetId:
					all_packets[idx] = hexString
					recovered = True
					#print("  Recovered %d" % packetId)
			if not recovered:
				#print("  %d is too or was recovered already" % packetId)
				pass
				
		elif expectedPacketId - packetId > 100 or expectedPacketId == -1:
			# packet counter looped back to 0, or we just reconnected to the client
			expectedPacketId = packetId + 1
			all_packets.append(hexString)
		
		elif packetId > expectedPacketId:
			# larger counter than expected. A packet was lost or sent out of order. Ask for the missing ones.
			#print("Expected %d but got %d" % (expectedPacketId, packetId))
			
			asked = 0
			for x in range(expectedPacketId, packetId):
				all_packets.append(x)
				if asked < 16: # more than this means total disconnect probably. Don't waste bandwidth
					udp_socket.sendto(x.to_bytes(2, 'big'), client_address)
				asked += 1
				#print("  Asked to resend %d" % x)
				
			expectedPacketId = packetId + 1
			all_packets.append(hexString)
		
		else:
			# normal packet update. Counter was incremented by 1 as expected
			expectedPacketId = packetId + 1
			all_packets.append(hexString)
			
		all_packets = send_packets_to_plugin(udp_socket, all_packets, False)
		
		if len(all_packets) > buffered_buffers*buffer_max*2:
			all_packets = all_packets[:-buffered_buffers*buffer_max*2]

t = Thread(target = command_loop, args =( ))
t.daemon = True
t.start()

receive_voice_data()