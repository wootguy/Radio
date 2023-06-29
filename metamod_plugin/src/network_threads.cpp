#include "network_threads.h"
#include "Socket.h"
#include "Channel.h"
#include "mmlib.h"
#include "radio.h"

#undef read
#include "mstream.h"

const int buffer_max = 4;
const int buffered_buffers = 1;
const int g_packet_streams = 1;

ThreadSafeQueue<string> g_packet_input;
ThreadSafeQueue<string> g_commands_out;
ThreadSafeQueue<string> g_commands_in;

thread* g_command_socket_thread;
thread* g_voice_socket_thread;
volatile bool g_plugin_exiting = false;
volatile uint64_t g_last_radio_online = 0;

void start_network_threads() {
	if (g_command_socket_thread || g_voice_socket_thread) {
		println("[Radio] Can't start network threads. Already started!");
		return;
	}
	g_plugin_exiting = false;
	g_last_radio_online = getEpochMillis();
	g_command_socket_thread = new thread(command_socket_thread, g_serverAddr->string);
	g_voice_socket_thread = new thread(voice_socket_thread, g_serverAddr->string);
}

void stop_network_threads() {
	println("[Radio] Waiting for network threads to join");

	if (g_command_socket_thread) {
		g_command_socket_thread->join();
		delete g_command_socket_thread;
		g_command_socket_thread = NULL;
	}

	if (g_voice_socket_thread) {
		g_voice_socket_thread->join();
		delete g_voice_socket_thread;
		g_voice_socket_thread = NULL;
	}

	println("[Radio] Network threads joined");
}

struct RecvPacket {
	vector<VoicePacket> data;
	bool wasReceived = false;
	uint16_t packetId = 0;

	RecvPacket() {}

	RecvPacket(vector<VoicePacket> data, uint16_t packetId) {
		this->data = data;
		this->packetId = packetId;
		wasReceived = true;
	}

	// constructor for packet that wasn't received
	RecvPacket(uint16_t packetId) {
		wasReceived = false;
		this->packetId = packetId;
	}
};

bool command_socket_connect(Socket& socket) {
	while (!socket.connect(1000)) {
		if (g_plugin_exiting) return false;
		this_thread::sleep_for(chrono::milliseconds(1000));
		if (g_plugin_exiting) return false;
	}

	return true;
}

void command_socket_thread(const char* addr) {
	println("[Radio] Connect TCP to: %s", addr);

	g_last_radio_online = getEpochMillis();

	Socket* commandSocket = new Socket(SOCKET_TCP | SOCKET_NONBLOCKING, IPV4(addr));

	command_socket_connect(*commandSocket);

	if (!g_plugin_exiting)
		println("[Radio] Command socket connected!");

	uint64_t lastHeartbeat = getEpochMillis();
	const float timeBetweenHeartbeats = 1.0f;

	while (!g_plugin_exiting) {
		uint64_t now = getEpochMillis();

		if (TimeDifference(lastHeartbeat, now) > timeBetweenHeartbeats) {
			lastHeartbeat = now;

			if (!commandSocket->send("\n", 1)) {
				println("[Radio] Command socket connection broken. Reconnecting...");
				this_thread::sleep_for(chrono::milliseconds(100));
				delete commandSocket;
				commandSocket = new Socket(SOCKET_TCP | SOCKET_NONBLOCKING, IPV4(addr));
				if (!command_socket_connect(*commandSocket)) {
					break;
				}
				println("[Radio] Command socket reconnected");
			}
			else {
				//println("Sent TCP heartbeat");
				g_last_radio_online = now;
			}
		}

		string commandOut;
		if (g_commands_out.dequeue(commandOut)) {
			//println("SEND SOCKET COMMAND: %s", commandOut.c_str());
			if (!commandSocket->send(commandOut.c_str(), commandOut.size())) {
				println("[Radio] Failed to send socket command '%s'", commandOut.c_str());
			}
		}

		Packet p;
		if (commandSocket->recv(p)) {
			string cmd = trimSpaces(p.getString());
			if (cmd.size()) {
				g_commands_in.enqueue(cmd);
			}
		}
		else {
			this_thread::sleep_for(chrono::milliseconds(200));
		}
	}

	delete commandSocket;
	println("[Radio] TCP thread finished");
}

void send_packets_to_plugin(Socket* socket, vector<RecvPacket>& all_packets, bool force_send) {
	if (all_packets.size() == 0)
		return;

	uint64_t now = getEpochMillis();
	int idealBufferSize = buffer_max * buffered_buffers;

	if (!force_send && all_packets.size() < idealBufferSize) {
		return;
	}

	int writeCount = all_packets.size();

	if (all_packets.size() > idealBufferSize) {
		writeCount = all_packets.size() - idealBufferSize;
	}

	int lost = 0;
	for (int i = 0; i < writeCount; i++) {
		RecvPacket& packet = all_packets[i];

		if (!packet.wasReceived) {
			lost += 1;

			string dat = UTIL_VarArgs("%0.4x", packet);
			for (int k = 0; k < g_packet_streams; k++) {
				dat += "00";
			}

			g_packet_input.enqueue(dat);
		}
		else if (!g_admin_pause_packets) {
			//print("Wrote %d" % len(packet));
			for (int i = 0; i < g_channelCount->value && i < packet.data.size(); i++) {
				g_channels[i].packetStream.enqueue(packet.data[i]);
			}

			if ((int)packet.data[packet.data.size() - 1].size > 500) {
				println("[Radio] Write %d voice!!", (int)packet.data[packet.data.size() - 1].size);
			}
			else {
				g_voice_data_stream.enqueue(packet.data[packet.data.size() - 1]);
			}
		}
	}

	all_packets.erase(all_packets.begin(), all_packets.begin() + min((int)all_packets.size(), buffer_max));

	int still_missing = 0;
	for (int i = 0; i < all_packets.size(); i++) {
		RecvPacket& packet = all_packets[i];

		if (!packet.wasReceived) {
			socket->send(&packet.packetId, 2); // TODO: client expects big endian
			still_missing += 1;
			println("[Radio]   Asked to resend %d", (int)packet.packetId);
		}
	}

	if (lost > 0) {
		println("[Radio] Lost %d packets", lost);
	}

	//println("Wrote %d packets (%d lost, %d buffered, %d requested)", buffer_max, lost, all_packets.size(), still_missing);
}

void voice_socket_thread(const char* addr) {
	println("[Radio] Connect UDP to: %s", addr);
	Socket* udp_socket = new Socket(SOCKET_UDP | SOCKET_NONBLOCKING, IPV4(addr));

	uint64_t lastHeartbeat = getEpochMillis();
	uint64_t last_packet_time = getEpochMillis();
	int expectedPacketId = -1;
	const float timeBetweenHeartbeats = 1.0f;
	bool is_connected = false;
	int g_packet_streams = 0;
	vector<RecvPacket> all_packets;

	while (!g_plugin_exiting) {
		uint64_t now = getEpochMillis();

		if (TimeDifference(lastHeartbeat, now) > timeBetweenHeartbeats) {
			lastHeartbeat = now;
			udp_socket->send("dere", 4);
			//println("Sent UDP heartbeat");
		}

		float time_since_last_packet = TimeDifference(last_packet_time, now);
		if (time_since_last_packet > 3) {
			expectedPacketId = -1;
			if (is_connected) {
				g_commands_in.enqueue("Radio server is now offline.");
				is_connected = false;
				send_packets_to_plugin(udp_socket, all_packets, true);
			}
		}

		Packet udp_packet;
		for (int i = 0; i < 10; i++) {
			if (udp_socket->recv(udp_packet)) {
				break;
			}

			this_thread::sleep_for(chrono::milliseconds(100));
		}

		if (udp_packet.sz <= -1 || !udp_packet.data) {
			//println("No udp data");
			continue;
		}

		last_packet_time = now;
		if (!is_connected)
			g_commands_in.enqueue("Radio server is online. Say .radio to use it.");
		is_connected = true;

		mstream data(udp_packet.data, udp_packet.sz);

		bool is_resent = udp_packet.sz > 6 && string(data.getBuffer(), 6) == "resent";
		if (is_resent)
			data.skip(6);

		uint16_t packetId;
		data.read(&packetId, 2);

		vector<VoicePacket> streamPackets;

		g_packet_streams = 0;
		while (!data.eom()) {
			uint16_t streamSize;
			data.read(&streamSize, 2);

			VoicePacket packet;
			packet.id = packetId;
			packet.size = 0;

			string sdat = "";

			for (int x = 0; x < streamSize; x++) {
				byte bval;
				data.read(&bval, 1);
				packet.data.push_back(bval);

				// combine into 32bit ints for faster writing later
				if (packet.data.size() == 4) {
					uint32 val = (packet.data[3] << 24) + (packet.data[2] << 16) + (packet.data[1] << 8) + packet.data[0];
					packet.ldata.push_back(val);
					packet.data.resize(0);
				}

				// combine into string for even faster writing later
				if (bval == 0) {
					packet.sdata.push_back(sdat);
					packet.ldata.resize(0);
					packet.data.resize(0);
					sdat = "";
				}
				else {
					sdat += (char)bval;
				}
			}

			packet.size = streamSize;
			streamPackets.push_back(packet);

			g_packet_streams += 1;
		}

		if (g_packet_streams - 1 < g_channelCount->value) {
			println("[Radio] Packet streams < channel count + 1 (%d %d)", g_packet_streams - 1, g_channelCount->value);
			logln("[Radio] Bad packet stream count: %d", (g_packet_streams - 1));
			continue; // don't let packet buffer sizes get out of sync between channels
		}

		//println("Got %d streams", totalStreams);
		//println("Got %d (%d bytes) (%d buffer)", packetId, (int)data.size(), (int)all_packets.size());

		if (is_resent) {
			// got a resent packet, which we asked for earlier
			bool recovered = false;
			for (int idx = 0; idx < all_packets.size(); idx++) {
				RecvPacket& packet = all_packets[idx];

				if (!packet.wasReceived && packet.packetId == packetId) {
					all_packets[idx].data = streamPackets;
					all_packets[idx].wasReceived = true;
					recovered = true;
					println("[Radio]   Recovered %d", packetId);
				}
			}
			if (!recovered) {
				println("[Radio]   %d is too old or was recovered already", packetId)
			}
		}
		else if (expectedPacketId - packetId > 100 || expectedPacketId == -1) {
			// packet counter looped back to 0, or we just reconnected to the client
			expectedPacketId = packetId + 1;
			all_packets.push_back(RecvPacket(streamPackets, packetId));
		}
		else if (packetId > expectedPacketId) {
			// larger counter than expected.A packet was lost or sent out of order.Ask for the missing ones.
			println("[Radio] Expected %d but got %d", expectedPacketId, packetId);

			int asked = 0;
			for (int x = expectedPacketId; x < packetId; x++) {
				all_packets.push_back(x);
				if (asked < 16) { // more than this means total disconnect probably.Don't waste bandwidth
					uint16_t xId = x;
					udp_socket->send(&xId, 2);
				}
				asked += 1;
				println("[Radio]   Asked to resend %d", x);
			}

			expectedPacketId = packetId + 1;
			all_packets.push_back(RecvPacket(streamPackets, packetId));
		}
		else {
			// normal packet update.Counter was incremented by 1 as expected
			expectedPacketId = packetId + 1;
			all_packets.push_back(RecvPacket(streamPackets, packetId));
		}

		send_packets_to_plugin(udp_socket, all_packets, false);
	}

	delete udp_socket;
	println("[Radio] UDP thread finished");
}
