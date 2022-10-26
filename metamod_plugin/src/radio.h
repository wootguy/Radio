#pragma once
#include "meta_utils.h"

enum MUTE_MODE {
	MUTE_NONE,
	MUTE_TTS,
	MUTE_VIDEOS,
	MUTE_MODES
};

enum SONG_LOAD_STATES {
	SONG_UNLOADED,
	SONG_LOADING,
	SONG_LOADED,
	SONG_FAILED,
	SONG_FINISHED // needed for videos that have no duration info
};

enum LAG_STATES {
	LAG_NONE,
	LAG_SEVERE_MSG,
	LAG_JOINING
};

struct Channel;

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

void ClientCommand(edict_t* pEntity);
void MapInit(edict_t* pEdictList, int edictCount, int clientMax);
void MapChange();
void StartFrame();
void radioThink();
void ClientJoin(edict_t* pEntity);
void ClientLeave(edict_t* pEntity);
void MessageBegin(int msg_dest, int msg_type, const float* pOrigin, edict_t* ed);
void writeChannelListeners();
void updateVoiceSlotIdx();
void loadChannelListeners();
void updateSleepState();
bool doCommand(edict_t* plr);
void showConsoleHelp(edict_t* plr, bool showChatMessage);

void send_voice_server_message(string msg);

extern map<string, PlayerState*> g_player_states;

extern const char* voice_server_file;

extern int g_radio_ent_idx;
extern int g_voice_ent_idx;
extern uint32_t g_song_id;
extern map<string, const char *> g_langs;
extern bool g_any_radio_listeners;
extern bool g_admin_pause_packets;
extern float g_packet_delay;

extern cvar_t* g_inviteCooldown;
extern cvar_t* g_requestCooldown;
extern cvar_t* g_djSwapCooldown;
extern cvar_t* g_skipSongCooldown;
extern cvar_t* g_djReserveTime;
extern cvar_t* g_djIdleTime;
extern cvar_t* g_maxQueue;
extern cvar_t* g_channelCount;

extern vector<Channel> g_channels;

#define MAX_SERVER_ACTIVE_SONGS 16
#define SONG_REQUEST_TIMEOUT 20
#define SONG_START_TIMEOUT 20 // max time to wait before cancelling a song that never started