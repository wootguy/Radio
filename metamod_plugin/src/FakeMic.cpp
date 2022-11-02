#include "FakeMic.h"
#include "radio.h"
#include "radio_utils.h"
#include "Channel.h"
#include <errno.h>
#include "network_threads.h"

uint32_t ideal_buffer_size = 8; // amount of packets to delay playback of. Higher = more latency + bad connection tolerance

float g_playback_start_time = 0;
float g_ideal_next_packet_time = 0;
int g_packet_idx = 0;
uint16 expectedNextPacketId = 0;

ThreadSafeQueue<VoicePacket> g_voice_data_stream;

const float BUFFER_DELAY = 0.7f; // minimum time for a voice packet to reach players (seems to actually be 4x longer...)

// using postThink hook instead of g_Scheduler so that music keeps playing during game_end screen
float g_next_play_samples = 0;
bool g_buffering_samples = false;

VoicePacket::VoicePacket(const VoicePacket& other) {
	this->id = other.id;
	this->size = other.size;
	this->sdata = other.sdata;
	this->ldata = other.ldata;
	this->data = other.data;
}

void FakeMicThink() {
	if (g_admin_pause_packets) {
		return;
	}
	float time = g_engfuncs.pfnTime();

	if (g_next_play_samples != -1 && time >= g_next_play_samples) {
		g_next_play_samples = -1;
		play_samples();
	}
}

void send_notification_delay(string msg, bool chatNotNotification) {
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
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
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
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
	println("[VoiceServerOut] " + msg);
	g_commands_out.enqueue(msg + "\n");
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
			if (!g_channels[c].packetStream.dequeue(packet)) {
				println("Missing packet for channel %d", c);
				continue;
			}
			g_channels[c].triggerPacketEvents(packet.id);
			speakerEnt = g_radio_ent_idx;
		}
		else {
			if (!g_voice_data_stream.dequeue(packet)) {
				println("Missing tts packet");
				continue;
			}
			speakerEnt = g_voice_ent_idx;
		}

		// trigger packet events for lost packets
		if (c == 0) {
			int packetId = packet.id;
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
		}

		channelPacketSizes += UTIL_VarArgs(" %3d", (int)packet.size);

		bool silentPacket = packet.size <= 2 && packet.data[0] == 0xff;
		//println("IDX " + g_radio_ent_idx + " " + g_voice_ent_idx);

		if (!silentPacket) {
			for (int i = 1; i <= gpGlobals->maxClients; i++) {
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