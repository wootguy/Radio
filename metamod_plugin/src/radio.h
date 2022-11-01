#pragma once
#include "meta_utils.h"
#include "PlayerState.h"

struct Channel;

void ClientCommand(edict_t* pEntity);
void MapInit(edict_t* pEdictList, int edictCount, int clientMax);
void StartFrame();
void radioThink();
void ClientJoin(edict_t* pEntity);
void ClientLeave(edict_t* pEntity);
void writeChannelListeners();
void updateVoiceSlotIdx();
void loadChannelListeners();
void updateSleepState();
bool doCommand(edict_t* plr);
void showConsoleHelp(edict_t* plr, bool showChatMessage);

void send_voice_server_message(string msg);

extern map<string, PlayerState*> g_player_states;

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
extern cvar_t* g_serverAddr;

extern vector<Channel> g_channels;

extern volatile bool g_plugin_exiting;

#define MAX_SERVER_ACTIVE_SONGS 16
#define SONG_REQUEST_TIMEOUT 20
#define SONG_START_TIMEOUT 20 // max time to wait before cancelling a song that never started