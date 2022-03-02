class VoicePacket {
	uint16 id;
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

array<VoicePacket> g_voice_data_stream;

string voice_server_file = "scripts/plugins/store/_tovoice.txt";
const float BUFFER_DELAY = 0.7f; // minimum time for a voice packet to reach players (seems to actually be 4x longer...)

// longer than this and python might overwrite what is currently being read
// keep this in sync with server.py
const float MAX_SAMPLE_LOAD_TIME = 0.1f; 

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

void load_samples() {
	if (!g_any_radio_listeners) {
		g_Scheduler.SetTimeout("load_samples", 1.0f);
		return;
	}

	File@ file = g_FileSystem.OpenFile(VOICE_FILE, OpenFile::READ);	

	if (file !is null && file.IsOpen()) {
		if (file.GetSize() == last_file_size) {
			g_Scheduler.SetTimeout("load_samples", file_check_interval);
			return; // file hasn't been updated yet
		}
	
		sample_load_start = g_EngineFuncs.Time();
		last_file_size = file.GetSize();
		load_packets_from_file(file, false);
	} else {
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
		
		g_channels[channel].cancelSong(songId);
		
		return;
	}

	bool chatNotNotify = msg[0] != '~';
	if (!chatNotNotify) {
		msg = msg.SubString(1);
	}
	send_notification("[Radio] " + msg + "\n", chatNotNotify);
}

void finish_sample_load(File@ file) {
	float loadTime = (g_EngineFuncs.Time() - sample_load_start) + file_check_interval + g_Engine.frametime;
	
	if (loadTime > MAX_SAMPLE_LOAD_TIME) {
		g_PlayerFuncs.ClientPrintAll(HUD_PRINTCONSOLE, "[Radio] Server can't load samples fast enough (" + loadTime + " / " + MAX_SAMPLE_LOAD_TIME + ")\n");
	}
	
	//println("Loaded samples from file in " + loadTime + " seconds");
	
	file.Close();
	load_samples();
}

void load_packets_from_file(File@ file, bool fastSend) {
	if (file.EOFReached()) {
		finish_sample_load(file);
		return;
	}
	
	string line;
	file.ReadLine(line);
	
	if (line.IsEmpty()) {
		finish_sample_load(file);
		return;
	}
	
	if (line[0] == 'm') {
		// server message, not a voice packet
		handle_radio_message(line.SubString(1));
	} else if (line[0] == 'z') {
		// random data to change the size of the file
	} else {
		uint16 packetId = (char_to_nibble[ uint(line[0]) ] << 12) + (char_to_nibble[ uint(line[1]) ] << 8) +
						  (char_to_nibble[ uint(line[2]) ] << 4) + (char_to_nibble[ uint(line[3]) ] << 0);
		
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
		
		if (parts.size()-1 != g_channels.size()+1) {
			println("Packet streams != channel count + 1 (" + (parts.size()-1) + " " + g_channels.size() + "): " + line);			
			finish_sample_load(file);
			return; // don't let packet buffer sizes get out of sync between channels
		}
		
		//println(line);
		
		for (uint c = 1; c < parts.size(); c++) {
			string packetString = parts[c];

			VoicePacket packet;
			packet.id = packetId;
			
			for (uint i = 0; i < packetString.Length()-1; i += 2) {
				uint n1 = char_to_nibble[ uint(packetString[i]) ];
				uint n2 = char_to_nibble[ uint(packetString[i + 1]) ];
				packet.data.insertLast((n1 << 4) + n2);
			}
			
			if (c-1 < g_channels.size()) {
				g_channels[c-1].packetStream.insertLast(packet);
			} else {
				g_voice_data_stream.insertLast(packet);
			}
			

			if (packetString.Length() % 2 == 1) {
				println("ODD LENGTH");
			}
		}
		
	}
	
	float loadTime = (g_EngineFuncs.Time() - sample_load_start) + file_check_interval + g_Engine.frametime;
	
	if (g_Engine.frametime > 0.025f || loadTime > MAX_SAMPLE_LOAD_TIME*0.5f) {
		// Send the rest of the packets now so the stream doesn't cut out.
		load_packets_from_file(file, true);
	} else {
		// Try not to impact frametimes too much.
		// The game has an annoying stutter when packets are loaded all at once.
		g_Scheduler.SetTimeout("load_packets_from_file", 0.0f, @file, false);
	}
}

void play_samples(bool buffering) {
	// all channels receive/send packets at the same time so it doesn't matter which channel is checked
	uint packetStreamSize = g_channels[0].packetStream.size();

	if (packetStreamSize < 1 or (buffering and packetStreamSize < ideal_buffer_size)) {
		if (!buffering) {
			send_debug_message("[Radio] Buffering voice packets...\n");
		}
		
		g_playback_start_time = g_EngineFuncs.Time();
		g_ideal_next_packet_time = g_playback_start_time + g_packet_idx*g_packet_delay;
		g_packet_idx = 1;
		
		send_debug_message("Buffering voice packets " + packetStreamSize + " / " + ideal_buffer_size + "\n");
		g_Scheduler.SetTimeout("play_samples", 0.1f, true);
		return;
	}
	
	string channelPacketSizes = "";
	int ttsChannelId = g_channels.size();
	
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
		
		channelPacketSizes += " " + formatInt(packet.data.size(), "", 3);
		
		bool silentPacket = packet.data.size() <= 4 and packet.data[0] == 0xff;
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
							g_PlayerFuncs.ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] Reliable packets started.");
						}
					}
					
					NetworkMessage m(sendMode, NetworkMessages::NetworkMessageType(53), plr.edict());
						m.WriteByte(speakerEnt); // entity which is "speaking"
						m.WriteShort(packet.data.size()); // compressed audio length
						for (uint k = 0; k < packet.data.size(); k++) {
							m.WriteByte(packet.data[k]);
						}
					m.End();
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
	
	if (nextDelay < 0) {
		play_samples(false);
	} else {
		g_Scheduler.SetTimeout("play_samples", nextDelay, false);
	}	
}