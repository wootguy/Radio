#pragma once
#include "meta_utils.h"

enum MUTE_MODE {
	MUTE_NONE,
	MUTE_TTS,
	MUTE_VIDEOS,
	MUTE_MODES
};

struct PlayerState {
	int channel = -1;
	map<string, float> lastInviteTime; // for invite cooldowns per player and for \everyone
	float lastRequest = -999; // for request cooldowns
	float lastDjToggle = -999; // for cooldown
	float lastSongSkip = -999; // for cooldown
	float lastLaggyCmd = -999; // for cooldown
	bool showHud = true;
	bool playAfterFullyLoaded = true; // toggle map music when fully loaded into the map
	bool neverUsedBefore = true;
	bool isDebugging = false;
	bool requestsAllowed = true;
	bool blockInvites = false;

	bool reliablePackets = false; // send packets on the reliable stream to fight packet loss
	bool startedReliablePackets = false;
	float reliablePacketsStart = 0; // delay before sending reliable packets on map start (prevent desyncs)

	int muteMode = MUTE_NONE;

	// text-to-speech settings
	string lang = "en";
	int pitch = 100;

	PlayerState() {}
};

void ClientCommand(edict_t* pEntity);
void MapInit(edict_t* pEdictList, int edictCount, int clientMax);
void StartFrame();
void radioThink();
void ClientJoin(edict_t* pEntity);
void MessageBegin(int msg_dest, int msg_type, const float* pOrigin, edict_t* ed);

extern map<string, PlayerState*> g_player_states;