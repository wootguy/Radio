class VoicePacket {
	uint16 id;
	uint size = 0;
	
	array<string> sdata;
	array<uint32> ldata;
	array<uint8> data;
}

float g_clock_adjust = 0; // adjustment made to sync the server clock with the packet times

const string VOICE_FILE = "scripts/plugins/store/_fromvoice.txt";
uint last_file_size = 0;
uint ideal_buffer_size = 8; // amount of packets to delay playback of. Higher = more latency + bad connection tolerance
float sample_load_start = 0;
int g_radio_ent_idx = 0;
int g_voice_ent_idx = 0;
float file_check_interval = 0.02f;

float g_playback_start_time = 0;
float g_ideal_next_packet_time = 0;
int g_packet_idx = 0;
uint16 expectedNextPacketId = 0;
float g_packet_delay = 0.05f;

bool g_admin_pause_packets = false;
bool g_lag_pause_packets = false;

array<VoicePacket> g_voice_data_stream;

string voice_server_file = "scripts/plugins/store/_tovoice.txt";
const float BUFFER_DELAY = 0.7f; // minimum time for a voice packet to reach players (seems to actually be 4x longer...)

// longer than this and python might overwrite what is currently being read
// keep this in sync with server.py
const float MAX_SAMPLE_LOAD_TIME = 0.15f - file_check_interval;

// convert lowercase hex letter to integer
array<uint8> char_to_nibble = {
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 1, 2, 3, 4, 5, 6, 7,
	8, 9, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 10, 11, 12, 13, 14, 15
};
const uint NIBBLE_MAX = char_to_nibble.size();

// using postThink hook instead of g_Scheduler so that music keeps playing during game_end screen
float g_next_load_samples = 0;
float g_next_play_samples = 0;
bool g_buffering_samples = false;
bool g_fast_loading = false;
bool g_finished_load = true;
File@ g_packet_in_file = null;

// can't append uint8 to strings directly (even with char cast), so using this lookup table instead
array<char> HEX_CODES = {
	'\x00','\x01','\x02','\x03','\x04','\x05','\x06','\x07','\x08','\x09','\x0A','\x0B','\x0C','\x0D','\x0E','\x0F',
	'\x10','\x11','\x12','\x13','\x14','\x15','\x16','\x17','\x18','\x19','\x1A','\x1B','\x1C','\x1D','\x1E','\x1F',
	'\x20','\x21','\x22','\x23','\x24','\x25','\x26','\x27','\x28','\x29','\x2A','\x2B','\x2C','\x2D','\x2E','\x2F',
	'\x30','\x31','\x32','\x33','\x34','\x35','\x36','\x37','\x38','\x39','\x3A','\x3B','\x3C','\x3D','\x3E','\x3F',
	'\x40','\x41','\x42','\x43','\x44','\x45','\x46','\x47','\x48','\x49','\x4A','\x4B','\x4C','\x4D','\x4E','\x4F',
	'\x50','\x51','\x52','\x53','\x54','\x55','\x56','\x57','\x58','\x59','\x5A','\x5B','\x5C','\x5D','\x5E','\x5F',
	'\x60','\x61','\x62','\x63','\x64','\x65','\x66','\x67','\x68','\x69','\x6A','\x6B','\x6C','\x6D','\x6E','\x6F',
	'\x70','\x71','\x72','\x73','\x74','\x75','\x76','\x77','\x78','\x79','\x7A','\x7B','\x7C','\x7D','\x7E','\x7F',
	'\x80','\x81','\x82','\x83','\x84','\x85','\x86','\x87','\x88','\x89','\x8A','\x8B','\x8C','\x8D','\x8E','\x8F',
	'\x90','\x91','\x92','\x93','\x94','\x95','\x96','\x97','\x98','\x99','\x9A','\x9B','\x9C','\x9D','\x9E','\x9F',
	'\xA0','\xA1','\xA2','\xA3','\xA4','\xA5','\xA6','\xA7','\xA8','\xA9','\xAA','\xAB','\xAC','\xAD','\xAE','\xAF',
	'\xB0','\xB1','\xB2','\xB3','\xB4','\xB5','\xB6','\xB7','\xB8','\xB9','\xBA','\xBB','\xBC','\xBD','\xBE','\xBF',
	'\xC0','\xC1','\xC2','\xC3','\xC4','\xC5','\xC6','\xC7','\xC8','\xC9','\xCA','\xCB','\xCC','\xCD','\xCE','\xCF',
	'\xD0','\xD1','\xD2','\xD3','\xD4','\xD5','\xD6','\xD7','\xD8','\xD9','\xDA','\xDB','\xDC','\xDD','\xDE','\xDF',
	'\xE0','\xE1','\xE2','\xE3','\xE4','\xE5','\xE6','\xE7','\xE8','\xE9','\xEA','\xEB','\xEC','\xED','\xEE','\xEF',
	'\xF0','\xF1','\xF2','\xF3','\xF4','\xF5','\xF6','\xF7','\xF8','\xF9','\xFA','\xFB','\xFC','\xFD','\xFE','\xFF'
};

HookReturnCode PlayerPostThink(CBasePlayer@ plr) {
	float time = g_EngineFuncs.Time();
	
	if (g_next_load_samples != -1 and time >= g_next_load_samples) {
		g_next_load_samples = -1;
		load_samples();
	}
	if (g_next_play_samples != -1 and time >= g_next_play_samples) {
		g_next_play_samples = -1;
		play_samples();
	}
	
	return HOOK_CONTINUE;
}

void load_samples() {
	if (!g_finished_load) {
		load_packets_from_file();
		return;
	}
	
	if (!g_any_radio_listeners || g_admin_pause_packets || g_lag_pause_packets) {
		g_next_load_samples = g_EngineFuncs.Time() + 1.0f;
		return;
	}

	@g_packet_in_file = @g_FileSystem.OpenFile(VOICE_FILE, OpenFile::READ);	

	if (g_packet_in_file !is null && g_packet_in_file.IsOpen()) {
		if (g_packet_in_file.GetSize() == last_file_size) {
			g_next_load_samples = g_EngineFuncs.Time() + file_check_interval;
			return; // file hasn't been updated yet
		}
	
		sample_load_start = g_EngineFuncs.Time();
		last_file_size = g_packet_in_file.GetSize();
		g_fast_loading = false;
		g_finished_load = false;
		load_packets_from_file();
	} else {
		println("[FakeMic] voice file not found: " + VOICE_FILE + "\n");
		g_Log.PrintF("[FakeMic] voice file not found: " + VOICE_FILE + "\n");
	}
}

void send_notification(string msg, bool chatNotNotification) {
	g_Scheduler.SetTimeout("send_notification_delay", BUFFER_DELAY, msg, chatNotNotification);
}

void send_notification_delay(string msg, bool chatNotNotification) {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		if (state.channel != -1 and chatNotNotification) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, msg);
		} else {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTNOTIFY, msg);
		}
	}
}

void send_debug_message(string msg) {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		if (state.isDebugging) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, msg);
		}
	}
}

void send_voice_server_message(string msg) {	
	File@ file = g_FileSystem.OpenFile( voice_server_file, OpenFile::APPEND );
	
	if (!file.IsOpen()) {
		string text = "[Radio] Failed to open: " + voice_server_file + "\n";
		println(text);
		g_Log.PrintF(text);
		return;
	}
	
	print("[VoiceServerOut] " + msg + "\n");
	file.Write(msg + "\n");
	file.Close();
}

void send_voice_server_message(CBasePlayer@ sender, string msg) {
	PlayerState@ state = getPlayerState(sender);
	string fmsg = "" + sender.pev.netname + "\\" + state.lang + "\\" + state.pitch + "\\" + msg;
	send_voice_server_message(fmsg);
}

void handle_radio_message(string msg) {
	println("[VoiceServerIn] " + msg);

	if (msg.Find("play:") == 0) {
		array<string> parts = msg.Split(":");
		int channel = atoi(parts[1]);
		uint songId = atoi(parts[2]);
		int packetId = atoi(parts[3]);
		int offset = atoi(parts[4]);
		int seconds = atoi(parts[5]);
		string title = "";
		
		for (uint i = 6; i < parts.size(); i++) {
			if (i != 6) {
				title = title + ":";
			}
			title += parts[i];
		}
		
		PacketListener listener;
		listener.packetId = packetId;
		listener.songId = songId;
		
		g_channels[channel].updateSongInfo(songId, title, seconds, offset);
		g_channels[channel].packetListeners.insertLast(listener);
		
		return;
	}
	
	if (msg.Find("info:") == 0) {
		array<string> parts = msg.Split(":");
		int channel = atoi(parts[1]);
		uint songId = atoi(parts[2]);
		int seconds = atoi(parts[3]);
		string title = "";
		
		for (uint i = 4; i < parts.size(); i++) {
			if (i != 4) {
				title = title + ":";
			}
			title += parts[i];
		}
		
		g_channels[channel].updateSongInfo(songId, title, seconds, 0);
		
		return;
	}
	
	if (msg.Find("fail:") == 0) {
		array<string> parts = msg.Split(":");
		int channel = atoi(parts[1]);
		uint songId = atoi(parts[2]);
		
		string reason = "";
		
		for (uint i = 3; i < parts.size(); i++) {
			if (i != 3) {
				reason = reason + ":";
			}
			reason += parts[i];
		}
		
		reason.Trim();
		
		g_channels[channel].cancelSong(songId, reason);
		
		return;
	}
	
	if (msg.Find("finish:") == 0) {
		array<string> parts = msg.Split(":");
		int channel = atoi(parts[1]);
		uint songId = atoi(parts[2]);
		
		g_channels[channel].finishSong(songId);
		
		return;
	}

	bool chatNotNotify = msg[0] != '~';
	if (!chatNotNotify) {
		msg = msg.SubString(1);
	}
	send_notification("[Radio] " + msg + "\n", chatNotNotify);
}

void finish_sample_load() {
	float loadTime = (g_EngineFuncs.Time() - sample_load_start) + file_check_interval + g_Engine.frametime;
	
	if (loadTime > MAX_SAMPLE_LOAD_TIME) {
		g_PlayerFuncs.ClientPrintAll(HUD_PRINTCONSOLE, "[Radio] Server can't load packets fast enough (" + loadTime + " / " + MAX_SAMPLE_LOAD_TIME + ")\n");
	}
	
	//println("Loaded samples from file in " + loadTime + " seconds");
	
	g_packet_in_file.Close();
	@g_packet_in_file = null;
	g_finished_load = true;
	load_samples();
}

void load_packets_from_file() {
	if (g_packet_in_file.EOFReached()) {
		finish_sample_load();
		return;
	}
	
	string line;
	g_packet_in_file.ReadLine(line);
	
	if (line.IsEmpty()) {
		finish_sample_load();
		return;
	}
	
	if (line[0] == 'm') {
		// server message, not a voice packet
		handle_radio_message(line.SubString(1));
	} else if (line[0] == 'z') {
		// random data to change the size of the file
	} else if (line.Length() > 4) {
		uint nib0 = uint(line[0]);
		uint nib1 = uint(line[1]);
		uint nib2 = uint(line[2]);
		uint nib3 = uint(line[3]);
		
		if (nib0 >= NIBBLE_MAX or nib1 >= NIBBLE_MAX or nib2 >= NIBBLE_MAX or nib3 >= NIBBLE_MAX) {
			g_Log.PrintF("[FakeMic] Bad packet line: " + line + "\n");
			finish_sample_load();
			return;
		}
	
		uint16 packetId = (char_to_nibble[nib0] << 12) + (char_to_nibble[nib1] << 8) +
						  (char_to_nibble[nib2] << 4) + (char_to_nibble[nib3] << 0);
		
		if (packetId != expectedNextPacketId) {
			//g_PlayerFuncs.ClientPrintAll(HUD_PRINTCONSOLE, "[Radio] Expected packet " + expectedNextPacketId + " but got " + packetId + "\n");
			
			for (int failsafe = 0; failsafe < 100 and expectedNextPacketId != packetId; failsafe++) {
				
				for (int c = 0; c < int(g_channels.size()); c++) {
					g_channels[c].triggerPacketEvents(expectedNextPacketId);
				}
				
				expectedNextPacketId += 1;
			}
		}
		expectedNextPacketId = packetId + 1;
						  
		array<string> parts = line.Split(":"); // packet_id : channel_1_packet : channel_2_packet : ...
		
		if (parts.size()-1 < g_channels.size()+1) {
			println("Packet streams > channel count + 1 (" + (parts.size()-1) + " " + g_channels.size() + "): " + line);	
			g_Log.PrintF("[FakeMic] Bad packet stream count: " + line + "\n");
			finish_sample_load();
			return; // don't let packet buffer sizes get out of sync between channels
		}
		
		//println(line);
		
		for (uint c = 1; c < parts.size(); c++) {
			string packetString = parts[c];

			VoicePacket packet;
			packet.id = packetId;
			
			string sdat = "";
			
			for (uint i = 0; i < packetString.Length()-1; i += 2) {
				uint n1 = char_to_nibble[ uint(packetString[i]) ];
				uint n2 = char_to_nibble[ uint(packetString[i + 1]) ];
				uint8 bval = (n1 << 4) + n2;
				packet.data.insertLast(bval);
				
				// combine into 32bit ints for faster writing later
				if (packet.data.size() == 4) {
					uint32 val = (packet.data[3] << 24) + (packet.data[2] << 16) + (packet.data[1] << 8) + packet.data[0];
					packet.ldata.insertLast(val);
					packet.data.resize(0);
				}
				
				// combine into string for even faster writing later
				if (bval == 0) {
					packet.sdata.insertLast(sdat);
					packet.ldata.resize(0);
					packet.data.resize(0);
					sdat = "";
				} else {
					sdat += HEX_CODES[bval];
				}
				
				packet.size++;
			}
			
			if (c == parts.size()-1) {
				g_voice_data_stream.insertLast(packet); // TTS data should always come last in steam_voice output
			}
			else if (c-1 < g_channels.size()) {
				g_channels[c-1].packetStream.insertLast(packet);
			}

			if (packetString.Length() % 2 == 1) {
				println("ODD LENGTH");
			}
		}
		
	}
	
	float loadTime = (g_EngineFuncs.Time() - sample_load_start) + file_check_interval + g_Engine.frametime;
	
	if (g_Engine.frametime > 0.025f || loadTime > MAX_SAMPLE_LOAD_TIME*0.5f || g_fast_loading) {
		// Send the rest of the packets now so the stream doesn't cut out.
		g_fast_loading = true;
		load_packets_from_file();
	} else {
		// Try not to impact frametimes too much.
		// The game has an annoying stutter when packets are loaded all at once.
		g_next_load_samples = g_EngineFuncs.Time() + 0.01f;
	}
}

void play_samples() {
	// all channels receive/send packets at the same time so it doesn't matter which channel is checked
	uint packetStreamSize = g_channels[0].packetStream.size();

	if (packetStreamSize < 1 or (g_buffering_samples and packetStreamSize < ideal_buffer_size)) {
		if (!g_buffering_samples) {
			send_debug_message("[Radio] Buffering voice packets...\n");
		}
		
		g_playback_start_time = g_EngineFuncs.Time();
		g_ideal_next_packet_time = g_playback_start_time + g_packet_idx*g_packet_delay;
		g_packet_idx = 1;
		
		send_debug_message("Buffering voice packets " + packetStreamSize + " / " + ideal_buffer_size + "\n");
		g_buffering_samples = true;
		g_next_play_samples = g_EngineFuncs.Time() + 0.1f;
		return;
	}
	
	string channelPacketSizes = "";
	int ttsChannelId = g_channels.size();
	
	int totalLoops = 0; // many thousands of loops = server lag
	
	for (int c = 0; c < int(g_channels.size()) + 1; c++) {
		VoicePacket packet;
		int speakerEnt = g_radio_ent_idx;
		
		if (c < ttsChannelId) {
			packet = g_channels[c].packetStream[0];
			g_channels[c].packetStream.removeAt(0);
			g_channels[c].triggerPacketEvents(packet.id);
			speakerEnt = g_radio_ent_idx;
		} else {
			packet = g_voice_data_stream[0];
			g_voice_data_stream.removeAt(0);
			speakerEnt = g_voice_ent_idx;
		}
		
		channelPacketSizes += " " + formatInt(packet.size, "", 3);
		
		bool silentPacket = packet.size < 4 and packet.data[0] == 0xff;
		//println("IDX " + g_radio_ent_idx + " " + g_voice_ent_idx);
		
		if (!silentPacket) {
			for ( int i = 1; i <= g_Engine.maxClients; i++ )
			{
				CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
				
				if (plr is null or !plr.IsConnected()) {
					continue;
				}
				
				PlayerState@ state = getPlayerState(plr);
				
				if (state.muteMode == MUTE_VIDEOS and c != ttsChannelId) {
					continue;
				}
				if (state.muteMode == MUTE_TTS and c == ttsChannelId) {
					continue;
				}
				
				if (c == state.channel || (c == ttsChannelId && state.channel != -1)) {
					NetworkMessageDest sendMode = state.reliablePackets ? MSG_ONE : MSG_ONE_UNRELIABLE;
					
					if (state.reliablePackets) {
						sendMode = MSG_ONE;
						
						if (state.reliablePacketsStart > g_EngineFuncs.Time()) {
							sendMode = MSG_ONE_UNRELIABLE;
						} else if (!state.startedReliablePackets) {
							state.startedReliablePackets = true;
							g_PlayerFuncs.ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] Reliable packets started.\n");
						}
					}
					
					// svc_voicedata
					NetworkMessage m(sendMode, NetworkMessages::NetworkMessageType(53), plr.edict());
						m.WriteByte(speakerEnt); // entity which is "speaking"
						m.WriteShort(packet.size); // compressed audio length
						
						// Ideally, packet data would be written once and re-sent to whoever wants it.
						// However there's no way to change the message destination after creation.
						// Data is combined into as few chunks as possible to minimize the loops
						// needed to write the data. An empty for-loop with thousands of iterations
						// can kill server performance so this is very important. This optimization
						// loops about 10% as much as writing bytes one-by-one for every player.

						// First, data is split into strings delimted by zeros. It can't all be one string
						// because a string can't contain zeros, and the data is not guaranteed to end with a 0.
						for (uint k = 0; k < packet.sdata.size(); k++) {
							m.WriteString(packet.sdata[k]); // includes the null terminater
						}
						
						// ...but that can leave a large chunk of bytes at the end, so the remainder is
						// also combined into 32bit ints.
						for (uint k = 0; k < packet.ldata.size(); k++) {
							m.WriteLong(packet.ldata[k]);
						}
						
						// whatever is left at this point will be less than 4 iterations.
						for (uint k = 0; k < packet.data.size(); k++) {
							m.WriteByte(packet.data[k]);
						}
						
					m.End();
					
					totalLoops += packet.sdata.size() + packet.ldata.size() + packet.data.size();
				}
			}
		}	
	}
	
	// try to keep buffer near ideal size
	//string logSpecial = silentPacket ? "silence " : "";
	string logSpecial = "";
	if (int(packetStreamSize) > ideal_buffer_size*1.2) {
		g_playback_start_time -= 0.05f;
		logSpecial = "Speedup 0.05";
	} else if (packetStreamSize > ideal_buffer_size) {
		g_playback_start_time -= 0.001f;
		logSpecial = "Speedup 0.001";
	} else if (packetStreamSize < 3) {
		g_playback_start_time += 0.001f;
		logSpecial = "Slowdown 0.001";
	}
	
	float serverTime = g_EngineFuncs.Time();
	float errorTime = g_ideal_next_packet_time - serverTime;
	
	g_ideal_next_packet_time = g_playback_start_time + g_packet_idx*(g_packet_delay - 0.0001f); // slightly fast to prevent mic getting quiet/choppy
	float nextDelay = (g_ideal_next_packet_time - serverTime) - g_Engine.frametime;
	
	send_debug_message("Sync: " + formatFloat(serverTime, "", 6, 3)
			+ " " + formatFloat(g_ideal_next_packet_time, "", 6, 3)
			+ " " + formatFloat(errorTime, "+", 3, 3)
			+ "   Delay: " + formatFloat(nextDelay, "", 6, 4)
			+ " " + formatFloat(g_Engine.frametime, "", 6, 4)
			+ "   Sz: " + channelPacketSizes
			+ "   Loops: " + formatInt(totalLoops, "", 3)
			+ "   Buff: " + formatInt(packetStreamSize, "", 2) + " / " + ideal_buffer_size +
			"  " + logSpecial + "\n");
	
	if (nextDelay > 0.5f) {
		nextDelay = 0.5f;
	}
	
	if (abs(errorTime) > 1.0f) {
		g_playback_start_time = g_EngineFuncs.Time();
		g_ideal_next_packet_time = g_playback_start_time + g_packet_idx*g_packet_delay;
		g_packet_idx = 1;
		println("Syncing packet time");
	}
	
	g_packet_idx++;
	
	g_buffering_samples = false;
	
	if (nextDelay < 0) {
		play_samples();
	} else {
		g_next_play_samples = g_EngineFuncs.Time() + nextDelay;
	}	
}