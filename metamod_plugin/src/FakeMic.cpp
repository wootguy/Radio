#include "FakeMic.h"
#include "radio.h"
#include "radio_utils.h"
#include "Channel.h"
#include <errno.h>

const char * VOICE_FILE = "svencoop/scripts/plugins/store/_fromvoice.txt";
uint32_t last_file_size = 0;
uint32_t ideal_buffer_size = 8; // amount of packets to delay playback of. Higher = more latency + bad connection tolerance
float sample_load_start = 0;
float file_check_interval = 0.02f;

float g_playback_start_time = 0;
float g_ideal_next_packet_time = 0;
int g_packet_idx = 0;
uint16 expectedNextPacketId = 0;

vector<VoicePacket> g_voice_data_stream;

const float BUFFER_DELAY = 0.7f; // minimum time for a voice packet to reach players (seems to actually be 4x longer...)

// longer than this and python might overwrite what is currently being read
// keep this in sync with server.py
const float MAX_SAMPLE_LOAD_TIME = 0.15f - file_check_interval;

// convert lowercase hex letter to integer
uint8_t char_to_nibble[] = {
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
const int NIBBLE_MAX = sizeof(char_to_nibble);

// using postThink hook instead of g_Scheduler so that music keeps playing during game_end screen
float g_next_load_samples = 0;
float g_next_play_samples = 0;
bool g_buffering_samples = false;
bool g_fast_loading = false;
bool g_finished_load = true;
FILE* g_packet_in_file = NULL;

void FakeMicThink() {
	float time = g_engfuncs.pfnTime();

	if (g_next_load_samples != -1 && time >= g_next_load_samples) {
		g_next_load_samples = -1;
		load_samples();
	}
	if (g_next_play_samples != -1 && time >= g_next_play_samples) {
		g_next_play_samples = -1;
		play_samples();
	}
}

void load_samples() {
	if (!g_finished_load) {
		load_packets_from_file();
		return;
	}

	if (!g_any_radio_listeners || g_admin_pause_packets) {
		g_next_load_samples = g_engfuncs.pfnTime() + 1.0f;
		return;
	}

	g_packet_in_file = fopen(VOICE_FILE, "r");

	if (g_packet_in_file) {
		uint32_t fsize = getFileSize(g_packet_in_file);

		if (fsize == last_file_size) {
			g_next_load_samples = g_engfuncs.pfnTime() + file_check_interval;
			fclose(g_packet_in_file);
			return; // file hasn't been updated yet
		}

		sample_load_start = g_engfuncs.pfnTime();
		last_file_size = fsize;
		g_fast_loading = false;
		g_finished_load = false;
		load_packets_from_file();
	}
	else {
		println(string("[FakeMic] voice file not found: ") + VOICE_FILE);
		logln(string("[FakeMic] voice file not found: ") + VOICE_FILE);
	}
}

void send_notification_delay(string msg, bool chatNotNotification) {
	for (int i = 1; i < gpGlobals->maxClients; i++) {
		edict_t* plr = INDEXENT(i);

		if (!isValidPlayer(plr)) {
			continue;
		}

		PlayerState& state = getPlayerState(plr);
		if (state.channel != -1 && chatNotNotification) {
			ClientPrint(plr, HUD_PRINTTALK, msg.c_str());
		}
		else {
			ClientPrint(plr, HUD_PRINTNOTIFY, msg.c_str());
		}
	}
}

void send_notification(string msg, bool chatNotNotification) {
	g_Scheduler.SetTimeout(send_notification_delay, BUFFER_DELAY, msg, chatNotNotification);
}

void send_debug_message(string msg) {
	for (int i = 1; i < gpGlobals->maxClients; i++) {
		edict_t* plr = INDEXENT(i);

		if (!isValidPlayer(plr)) {
			continue;
		}

		PlayerState& state = getPlayerState(plr);
		if (state.isDebugging) {
			ClientPrint(plr, HUD_PRINTCONSOLE, msg.c_str());
		}
	}
}

void send_voice_server_message(string msg) {
	errno = 0;
	FILE* file = fopen(voice_server_file, "a");

	if (!file) {
		string text = UTIL_VarArgs("[Radio] Failed to open: %s (%d)\n", voice_server_file, errno);
		println(text);
		logln(text);
		return;
	}

	//g_engfuncs.pfnTime();

	print("[VoiceServerOut] " + msg + "\n");
	fprintf(file, (msg + "\n").c_str());
	fclose(file);
}

void send_voice_server_message(edict_t* sender, string msg) {
	PlayerState& state = getPlayerState(sender);
	string fmsg = UTIL_VarArgs("%s\\%s\\%d\\%s", STRING(sender->v.netname), state.lang.c_str(), state.pitch, msg.c_str());
	send_voice_server_message(fmsg);
}

void handle_radio_message(string msg) {
	println("[VoiceServerIn] " + msg);

	if (msg.find("play:") == 0) {
		vector<string> parts = splitString(msg, ":");
		int channel = atoi(parts[1].c_str());
		uint32_t songId = atoi(parts[2].c_str());
		int packetId = atoi(parts[3].c_str());
		int offset = atoi(parts[4].c_str());
		int seconds = atoi(parts[5].c_str());
		string title = "";

		for (int i = 6; i < parts.size(); i++) {
			if (i != 6) {
				title = title + ":";
			}
			title += parts[i];
		}

		PacketListener listener;
		listener.packetId = packetId;
		listener.songId = songId;

		g_channels[channel].updateSongInfo(songId, title, seconds, offset);
		g_channels[channel].packetListeners.push_back(listener);

		return;
	}

	if (msg.find("info:") == 0) {
		vector<string> parts = splitString(msg, ":");
		int channel = atoi(parts[1].c_str());
		uint32_t songId = atoi(parts[2].c_str());
		int seconds = atoi(parts[3].c_str());
		string title = "";

		for (int i = 4; i < parts.size(); i++) {
			if (i != 4) {
				title = title + ":";
			}
			title += parts[i];
		}

		g_channels[channel].updateSongInfo(songId, title, seconds, 0);

		return;
	}

	if (msg.find("fail:") == 0) {
		vector<string> parts = splitString(msg, ":");
		int channel = atoi(parts[1].c_str());
		uint32_t songId = atoi(parts[2].c_str());

		string reason = "";

		for (int i = 3; i < parts.size(); i++) {
			if (i != 3) {
				reason = reason + ":";
			}
			reason += parts[i];
		}

		reason = trimSpaces(reason);

		g_channels[channel].cancelSong(songId, reason);

		return;
	}

	if (msg.find("finish:") == 0) {
		vector<string> parts = splitString(msg, ":");
		int channel = atoi(parts[1].c_str());
		uint32_t songId = atoi(parts[2].c_str());

		g_channels[channel].finishSong(songId);

		return;
	}

	bool chatNotNotify = msg[0] != '~';
	if (!chatNotNotify) {
		msg = msg.substr(1);
	}
	send_notification("[Radio] " + msg + "\n", chatNotNotify);
}

void finish_sample_load() {
	float loadTime = g_engfuncs.pfnTime() - sample_load_start + file_check_interval + gpGlobals->frametime;

	if (loadTime > MAX_SAMPLE_LOAD_TIME) {
		ClientPrintAll(HUD_PRINTCONSOLE, UTIL_VarArgs("[Radio] Server can't load packets fast enough (%.2f / %.2f)\n", loadTime, MAX_SAMPLE_LOAD_TIME));
	}

	//println("Loaded samples from file in " + loadTime + " seconds");

	fclose(g_packet_in_file);
	g_packet_in_file = NULL;
	g_finished_load = true;
	load_samples();
}

void load_packets_from_file() {
	string line;

	if (!cgetline(g_packet_in_file, line) || line.empty()) {
		finish_sample_load();
		return;
	}

	if (line[0] == 'm') {
		// server message, not a voice packet
		handle_radio_message(line.substr(1));
	}
	else if (line[0] == 'z') {
		// random data to change the size of the file
	}
	else if (line.length() > 4) {
		char nib0 = line[0];
		char nib1 = line[1];
		char nib2 = line[2];
		char nib3 = line[3];

		if (nib0 >= NIBBLE_MAX || nib1 >= NIBBLE_MAX || nib2 >= NIBBLE_MAX || nib3 >= NIBBLE_MAX) {
			logln("[FakeMic] Bad packet line: " + line + "\n");
			finish_sample_load();
			return;
		}

		uint16 packetId = (char_to_nibble[nib0] << 12) + (char_to_nibble[nib1] << 8) +
			(char_to_nibble[nib2] << 4) + (char_to_nibble[nib3] << 0);

		if (packetId != expectedNextPacketId) {
			//g_PlayerFuncs.ClientPrintAll(HUD_PRINTCONSOLE, "[Radio] Expected packet " + expectedNextPacketId + " but got " + packetId + "\n");

			for (int failsafe = 0; failsafe < 100 && expectedNextPacketId != packetId; failsafe++) {

				for (int c = 0; c < int(g_channels.size()); c++) {
					g_channels[c].triggerPacketEvents(expectedNextPacketId);
				}

				expectedNextPacketId += 1;
			}
		}
		expectedNextPacketId = packetId + 1;

		vector<string> parts = splitString(line, ":"); // packet_id : channel_1_packet : channel_2_packet : ...

		if (parts.size() - 1 < g_channels.size() + 1) {
			println("Packet streams > channel count + 1 (%d %d): %s", parts.size() - 1, g_channels.size(), line.c_str());
			logln("[FakeMic] Bad packet stream count: " + line + "\n");
			finish_sample_load();
			return; // don't let packet buffer sizes get out of sync between channels
		}

		//println(line);

		for (int c = 1; c < parts.size(); c++) {
			string packetString = parts[c];

			VoicePacket packet;
			packet.id = packetId;

			string sdat = "";

			for (int i = 0; i < packetString.length() - 1; i += 2) {
				uint8_t n1 = char_to_nibble[packetString[i]];
				uint8_t n2 = char_to_nibble[packetString[i + 1]];
				uint8_t bval = (n1 << 4) + n2;
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

				packet.size++;
			}

			if (c == parts.size() - 1) {
				g_voice_data_stream.push_back(packet); // TTS data should always come last in steam_voice output
			}
			else if (c - 1 < g_channels.size()) {
				g_channels[c - 1].packetStream.push_back(packet);
			}

			if (packetString.length() % 2 == 1) {
				println("ODD LENGTH '%s'", packetString.c_str());
			}
		}

	}

	float loadTime = (g_engfuncs.pfnTime() - sample_load_start) + file_check_interval + gpGlobals->frametime;

	if (gpGlobals->frametime > 0.025f || loadTime > MAX_SAMPLE_LOAD_TIME * 0.5f || g_fast_loading) {
		// Send the rest of the packets now so the stream doesn't cut out.
		g_fast_loading = true;
		load_packets_from_file();
	}
	else {
		// Try not to impact frametimes too much.
		// The game has an annoying stutter when packets are loaded all at once.
		g_next_load_samples = g_engfuncs.pfnTime() + 0.01f;
	}
}

void play_samples() {
	// all channels receive/send packets at the same time so it doesn't matter which channel is checked
	uint32_t packetStreamSize = g_channels[0].packetStream.size();

	if (packetStreamSize < 1 || (g_buffering_samples && packetStreamSize < ideal_buffer_size)) {
		if (!g_buffering_samples) {
			send_debug_message("[Radio] Buffering voice packets...\n");
		}

		g_playback_start_time = g_engfuncs.pfnTime();
		g_ideal_next_packet_time = g_playback_start_time + g_packet_idx * g_packet_delay;
		g_packet_idx = 1;

		send_debug_message(UTIL_VarArgs("Buffering voice packets %d / %d\n", packetStreamSize, ideal_buffer_size));
		g_buffering_samples = true;
		g_next_play_samples = g_engfuncs.pfnTime() + 0.1f;
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
			g_channels[c].packetStream.erase(g_channels[c].packetStream.begin());
			g_channels[c].triggerPacketEvents(packet.id);
			speakerEnt = g_radio_ent_idx;
		}
		else {
			packet = g_voice_data_stream[0];
			g_voice_data_stream.erase(g_voice_data_stream.begin());
			speakerEnt = g_voice_ent_idx;
		}

		channelPacketSizes += UTIL_VarArgs(" %3d", packet.size);

		bool silentPacket = packet.size < 4 && packet.data[0] == 0xff;
		//println("IDX " + g_radio_ent_idx + " " + g_voice_ent_idx);

		if (!silentPacket) {
			for (int i = 1; i < gpGlobals->maxClients; i++) {
				edict_t* plr = INDEXENT(i);

				if (!isValidPlayer(plr)) {
					continue;
				}

				PlayerState& state = getPlayerState(plr);

				if (state.muteMode == MUTE_VIDEOS && c != ttsChannelId) {
					continue;
				}
				if (state.muteMode == MUTE_TTS && c == ttsChannelId) {
					continue;
				}

				if (c == state.channel || (c == ttsChannelId && state.channel != -1)) {
					int sendMode = state.reliablePackets ? MSG_ONE : MSG_ONE_UNRELIABLE;

					if (state.reliablePackets) {
						sendMode = MSG_ONE;

						if (state.reliablePacketsStart > g_engfuncs.pfnTime()) {
							sendMode = MSG_ONE_UNRELIABLE;
						}
						else if (!state.startedReliablePackets) {
							state.startedReliablePackets = true;
							ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] Reliable packets started.\n");
						}
					}

					// svc_voicedata
					MESSAGE_BEGIN(sendMode, 53, NULL, plr);
					WRITE_BYTE(speakerEnt); // entity which is "speaking"
					WRITE_SHORT(packet.size); // compressed audio length

					// Ideally, packet data would be written once and re-sent to whoever wants it.
					// However there's no way to change the message destination after creation.
					// Data is combined into as few chunks as possible to minimize the loops
					// needed to write the data. This optimization loops about 10% as much as 
					// writing bytes one-by-one for every player.

					// First, data is split into strings delimted by zeros. It can't all be one string
					// because a string can't contain zeros, and the data is not guaranteed to end with a 0.
					for (int k = 0; k < packet.sdata.size(); k++) {
						WRITE_STRING(packet.sdata[k].c_str()); // includes the null terminater
					}

					// ...but that can leave a large chunk of bytes at the end, so the remainder is
					// also combined into 32bit ints.
					for (int k = 0; k < packet.ldata.size(); k++) {
						WRITE_LONG(packet.ldata[k]);
					}

					// whatever is left at this point will be less than 4 iterations.
					for (int k = 0; k < packet.data.size(); k++) {
						WRITE_BYTE(packet.data[k]);
					}

					MESSAGE_END();

					totalLoops += packet.sdata.size() + packet.ldata.size() + packet.data.size();
				}
			}
		}
	}

	// try to keep buffer near ideal size
	//string logSpecial = silentPacket ? "silence " : "";
	string logSpecial = "";
	if (int(packetStreamSize) > ideal_buffer_size * 1.2) {
		g_playback_start_time -= 0.05f;
		logSpecial = "Speedup 0.05";
	}
	else if (packetStreamSize > ideal_buffer_size) {
		g_playback_start_time -= 0.001f;
		logSpecial = "Speedup 0.001";
	}
	else if (packetStreamSize < 3) {
		g_playback_start_time += 0.001f;
		logSpecial = "Slowdown 0.001";
	}

	float serverTime = g_engfuncs.pfnTime();
	float errorTime = g_ideal_next_packet_time - serverTime;

	g_ideal_next_packet_time = g_playback_start_time + g_packet_idx * (g_packet_delay - 0.0001f); // slightly fast to prevent mic getting quiet/choppy
	float nextDelay = (g_ideal_next_packet_time - serverTime) - gpGlobals->frametime;

	send_debug_message(UTIL_VarArgs(
		"Sync: %6.3f %6.3f %+3.3f   Delay: %6.4f %6.4f   Sz: %s   Loops: %3d   Buff: %2d / %d %s\n",
		serverTime,
		g_ideal_next_packet_time,
		errorTime,
		nextDelay,
		gpGlobals->frametime,
		channelPacketSizes.c_str(),
		totalLoops,
		packetStreamSize,
		ideal_buffer_size,
		logSpecial.c_str()));

	if (nextDelay > 0.5f) {
		nextDelay = 0.5f;
	}

	if (abs(errorTime) > 1.0f) {
		g_playback_start_time = g_engfuncs.pfnTime();
		g_ideal_next_packet_time = g_playback_start_time + g_packet_idx * g_packet_delay;
		g_packet_idx = 1;
		println("Syncing packet time");
	}

	g_packet_idx++;

	g_buffering_samples = false;

	if (nextDelay < 0) {
		play_samples();
	}
	else {
		g_next_play_samples = g_engfuncs.pfnTime() + nextDelay;
	}
}