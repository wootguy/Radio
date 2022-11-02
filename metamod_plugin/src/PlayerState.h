#pragma once
#include "meta_utils.h"
#include "message_overrides.h"
#include <map>
#include <string>

enum MUTE_MODE {
	MUTE_NONE,
	MUTE_TTS,
	MUTE_VIDEOS,
	MUTE_MODES
};

struct PlayerState {
	int channel = -1;
	map<string, float> lastInviteTime; // for invite cooldowns per player and for \everyone
	vector<LoopingSound> activeMapMusic;
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
	bool startedReliablePackets = false;

	bool reliablePackets = false; // send packets on the reliable stream to fight packet loss
	float reliablePacketsStart = 0; // delay before sending reliable packets on map start (prevent desyncs)

	int muteMode = MUTE_NONE;

	// text-to-speech settings
	string lang = "en";
	int pitch = 100;

	PlayerState() {}

	bool shouldInviteCooldown(edict_t* plr, string id);
	bool shouldRequestCooldown(edict_t* plr);
	bool shouldDjToggleCooldown(edict_t* plr);
	bool shouldSongSkipCooldown(edict_t* plr);
	bool shouldCooldownGeneric(edict_t* plr, float lastActionTime, int cooldownTime, string actionDesc);
	bool isRadioMusicPlaying();
};