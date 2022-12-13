#include "radio.h"
#include <string>
#include "enginecallback.h"
#include "eiface.h"
#include "radio_utils.h"
#include "TextMenu.h"
#include <algorithm>
#include "Channel.h"
#include "menus.h"
#include <thread>
#include "ThreadSafeQueue.h"
#include "mstream.h"
#include "Socket.h"
#include "network_threads.h"
#include "message_overrides.h"

using namespace std;

// dj ejected for inactivity but it was no one and never was one
// chatsounds are muted?

// TODO:
// - show who else is listening with music sprites or smth
// - invite cooldowns should use datetime
// - read volume level from ambient_music when scripts are able to read it from the bsp
// - set voice ent to DJ or requester if server is full, instead of player 0
// - option to block requests from specific player
// - delete cached link info after a while
// - radio offline/online message shouldnt show when packets are paused
// - Failed to play a video error is global
// - warning message for dj ejection
// - player becomes null now maybe because id update changes
// - failed to play message happens twice
// - allow changing target volume
// - playback failing again with ytdl lib update
// os.startfile(sys.argv[0])
// sys.exit()

// test links:
// https://youtu.be/GXv1hDICJK0 (age restricted)
// https://youtu.be/-zEJEdbZUP8 (crashes or doesn't play on yt-dlp)
// https://www.youtube.com/shorts/U4WTB8-ssRM (pafy doesn't find right link)
// https://www.youtube.com/watch?v=5-uBerhQvTc (video unavailable)
// https://youtu.be/5-uBerhQvTc (video unavailable)
// https://archive.org/details/your-cum-wont-last-official-music-video-7-do-70nzt-rne (download url has special chars)
// https://soundcloud.com/felix-adjapong/e-40-choices-yup-instrumental-prod-by-poly-boy
// https://kippykip.com/data/video/0/634-7d3e1a675391cfabca5710e6af52a386.mov (generic backend + no duration info)
// https://www.youtube.com/watch?v=fUgzv-8_EMc (live stream)

// Description of plugin
plugin_info_t Plugin_info = {
	META_INTERFACE_VERSION,	// ifvers
	"Radio",	// name
	"1.0",	// version
	__DATE__,	// date
	"w00tguy",	// author
	"https://github.com/wootguy/",	// url
	"RADIO",	// logtag, all caps please
	PT_ANYTIME,	// (when) loadable
	PT_ANYPAUSE,	// (when) unloadable
};

vector<Channel> g_channels;
const char * channel_listener_file = "svencoop/scripts/plugins/store/radio_listeners.txt";

uint32_t g_song_id = 1;
bool g_any_radio_listeners = false;

// player slot to associate voice data with (will display "(null)" for empty slots)
int g_radio_ent_idx = 0;
int g_voice_ent_idx = 0;

volatile bool g_admin_pause_packets = false;

float g_packet_delay = 0.05f;

#define MAX_CHANNELS 4

cvar_t* g_inviteCooldown;
cvar_t* g_requestCooldown;
cvar_t* g_djSwapCooldown;
cvar_t* g_skipSongCooldown;
cvar_t* g_djReserveTime;
cvar_t* g_djIdleTime;
cvar_t* g_maxQueue;
cvar_t* g_channelCount;
cvar_t* g_serverAddr;
cvar_t* g_enableMessageHooks;

// hack
cvar_t* g_relaySayMsg;

enum angelscript_chat_flags {
	ASCHAT_HANDLED, // a plugin handled the current chat message
	ASCHAT_UNHANDLED, // chat was not handled by any angelscript plugins
	ASCHAT_HIDDEN // a plugin wants the message to be hidden, but allowed other plugins to process the chat
};

// cvar that indicates when a chat message is handled by an angelscript plugin.
// Defined by the AsChatFlag plugin
cvar_t* g_angelscript_chat_flag = NULL;

// client command args used across pre/post hooks
CommandArgs g_args = CommandArgs();

map<string, PlayerState*> g_player_states;

bool g_is_server_changing_levels = false;
uint64_t lastMapMusicDebug = 0;

void ServerDeactivate() {
	g_is_server_changing_levels = true;
	RETURN_META(MRES_IGNORED);
}

void PluginInit() {
	g_plugin_exiting = false;

	g_dll_hooks.pfnClientCommand = ClientCommand;
	g_dll_hooks_post.pfnClientCommand = ClientCommand_post;
	g_dll_hooks.pfnServerActivate = MapInit;
	g_dll_hooks.pfnStartFrame = StartFrame;
	g_dll_hooks.pfnClientPutInServer = ClientJoin;
	g_dll_hooks.pfnClientDisconnect = ClientLeave;
	g_dll_hooks.pfnServerDeactivate = ServerDeactivate;

	g_engine_hooks.pfnMessageBegin = MessageBegin;
	g_engine_hooks.pfnWriteAngle = WriteAngle;
	g_engine_hooks.pfnWriteByte = WriteByte;
	g_engine_hooks.pfnWriteChar = WriteChar;
	g_engine_hooks.pfnWriteCoord = WriteCoord;
	g_engine_hooks.pfnWriteEntity = WriteEntity;
	g_engine_hooks.pfnWriteLong = WriteLong;
	g_engine_hooks.pfnWriteShort = WriteShort;
	g_engine_hooks.pfnWriteString = WriteString;
	g_engine_hooks.pfnMessageEnd = MessageEnd;
	g_engine_hooks_post.pfnMessageEnd = MessageEnd_post;
	
	g_inviteCooldown = RegisterCVar("radio.inviteCooldown", "600", 600, 0);
	g_requestCooldown = RegisterCVar("radio.requestCooldown", "300", 300, 0);
	g_djSwapCooldown = RegisterCVar("radio.djSwapCooldown", "5", 5, 0);
	g_skipSongCooldown = RegisterCVar("radio.skipSongCooldown", "10", 10, 0);
	g_djReserveTime = RegisterCVar("radio.djReserveTime", "240", 240, 0);
	g_djIdleTime = RegisterCVar("radio.djIdleTime", "180", 180, 0);
	g_maxQueue = RegisterCVar("radio.maxQueue", "8", 8, 0);
	g_channelCount = RegisterCVar("radio.channelCount", "1", 0, 0);
	g_serverAddr = RegisterCVar("radio.serverIp", "127.0.0.1:1337", 0, 0);
	g_enableMessageHooks = RegisterCVar("radio.messageHooks", "1", 1, 0);

	g_relaySayMsg = RegisterCVar("relay_say_msg", "0", 0, 0);

	if (g_channelCount->value > MAX_CHANNELS) {
		g_channelCount->value = MAX_CHANNELS;
	}

	g_channels.resize(MAX_CHANNELS);
	for (int i = 0; i < MAX_CHANNELS; i++) {
		g_channels[i].name = string("Channel ") + to_string(i + 1);
		g_channels[i].id = i;
		g_channels[i].maxStreams = 3;
	}

	g_Scheduler.SetInterval(radioThink, 0.5f, -1);
	g_Scheduler.SetInterval(writeChannelListeners, 60*10, -1);
	g_Scheduler.SetInterval(updateVoiceSlotIdx, 3, -1);

	play_samples();

	send_voice_server_message("Radio\\en\\100\\.radio stop global");
	send_voice_server_message("Radio\\en\\100\\.pause_packets");

	loadChannelListeners();
	updateSleepState();

	LoadAdminList();

	if (gpGlobals->time > 3.0f) {
		loadSoundCacheFile();
		start_network_threads();
	}

	g_main_thread_id = std::this_thread::get_id();
}

void handleThreadPrints() {
	string msg;
	for (int failsafe = 0; failsafe < 10; failsafe++) {
		if (g_thread_prints.dequeue(msg)) {
			println(msg.c_str());
		}
		else {
			break;
		}
	}

	for (int failsafe = 0; failsafe < 10; failsafe++) {
		if (g_thread_logs.dequeue(msg)) {
			logln(msg.c_str());
		}
		else {
			break;
		}
	}

	if (g_commands_in.dequeue(msg)) {
		handle_radio_message(msg);
	}
	
}

void mapMusicDebug() {
	uint64_t now = getEpochMillis();
	if (TimeDifference(lastMapMusicDebug, now) < 0.1f) {
		return;
	}
	lastMapMusicDebug = now;

	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* plr = INDEXENT(i);

		if (!isValidPlayer(plr)) {
			continue;
		}

		PlayerState& state = getPlayerState(plr);
		if (!state.isMapMusicDebug) {
			continue;
		}

		hudtextparms_t params = { 0 };
		params.effect = 0;
		params.fadeinTime = 0;
		params.fadeoutTime = 0.5f;
		params.holdTime = 1.0f;
		params.r1 = 255;
		params.g1 = 255;
		params.b1 = 255;

		params.x = 0;
		params.y = 0.2f;
		params.channel = 1;

		string msg = "Map music:";
		for (int k = 0; k < state.activeMapMusic.size(); k++) {
			LoopingSound& snd = state.activeMapMusic[k];
			//const char* ent = snd.info.entindex >= 0 ? STRING(INDEXENT(snd.info.entindex)->v.targetname) : UTIL_VarArgs("%d", snd.info.entindex);
			const char* playing = snd.isPlaying ? "playing" : "paused";

			msg += UTIL_VarArgs("\n%d) %s (%s)", 
				k+1, snd.info.getDesc(), playing);
		}

		HudMessage(plr, params, msg.c_str(), MSG_ONE_UNRELIABLE);
	}
}

const int lastChannelCount = -1;

void StartFrame() {
	if (g_channelCount->value > MAX_CHANNELS) {
		g_engfuncs.pfnCVarSetFloat("radio.channelCount", MAX_CHANNELS);
	}

	if (lastChannelCount != g_channelCount->value) {
		if (g_channelCount->value == 1) {
			g_channels[0].name = "Radio";
			g_channels[0].spamMode = false;
			g_channels[0].maxStreams = 12;
		}
		else {
			g_channels[0].spamMode = true;
			g_channels[0].maxStreams = 6;
		}
	}

	g_Scheduler.Think();
	FakeMicThink();

	handleThreadPrints();

	mapMusicDebug();

	RETURN_META(MRES_IGNORED);
}

void menuCallback(edict_t* pEntity, int iSelect, string option) {
	ClientPrint(pEntity, HUD_PRINTNOTIFY, "ZOMG CHOSE %s", option.c_str());
}

int getAngelscriptChatFlag() {
	if (!g_angelscript_chat_flag) {
		const char* as_chat_flag_cvar_name = "angelscript_chat_flag";
		g_angelscript_chat_flag = g_engfuncs.pfnCVarGetPointer(as_chat_flag_cvar_name);

		if (!g_angelscript_chat_flag) {
			println("Failed to get cvar pointer for '%s'", as_chat_flag_cvar_name);
			return ASCHAT_UNHANDLED;
		}
	}

	return g_angelscript_chat_flag->value;
}

// called before angelscript hooks
void ClientCommand(edict_t* pEntity) {
	TextMenuClientCommandHook(pEntity);

	META_RES ret = doCommand(pEntity) ? MRES_SUPERCEDE : MRES_IGNORED;

	RETURN_META(ret);
}

// called after angelscript hooks
void ClientCommand_post(edict_t* plr) {
	int flag = getAngelscriptChatFlag();

	if (flag == ASCHAT_HANDLED || flag == ASCHAT_HIDDEN) {
		RETURN_META(MRES_IGNORED);
	}
	
	CommandArgs& args = g_args;
	string lowerArg = toLowerCase(args.ArgV(0));

	if (args.isConsoleCmd) {
		RETURN_META(MRES_IGNORED);
	}

	// at this point we know that angelscript didn't handle this chat message 	
	// so there's little risk of sending chat commands to text-to-speech

	PlayerState& state = getPlayerState(plr);

	if (lowerArg.length() > 0) {
		if (g_any_radio_listeners && lowerArg.find("https://") != 0 && lowerArg.find("http://") != 0) {
			// speak the message
			send_voice_server_message(UTIL_VarArgs("%s\\%s\\%d\\%s", STRING(plr->v.netname), state.lang.c_str(), state.pitch, args.getFullCommand().c_str()));
		}
	}

	RETURN_META(MRES_IGNORED);
}

void PluginExit() {
	g_plugin_exiting = true;
	writeChannelListeners();

	stop_network_threads();

	println("Plugin exit finish");
}

void writeChannelListeners() {
	FILE* file = fopen(channel_listener_file, "w");

	if (!file) {
		string text = string("[Radio] Failed to open: ") + channel_listener_file + "\n";
		println(text);
		logln(text);
		return;
	}

	vector<vector<string>> radio_listeners;
	for (int i = 0; i < g_channels.size(); i++) {
		radio_listeners.push_back(vector<string>());
	}
	int numWrites = 0;

	for (auto const& item : g_player_states)
	{
		PlayerState& state = *item.second;
		if (state.channel >= 0 && state.channel < int(g_channels.size())) {
			radio_listeners[state.channel].push_back(item.first);
		}
	}

	for (int i = 0; i < g_channels.size(); i++) {
		fprintf(file, "\\%d\\\n", i);

		for (int k = 0; k < radio_listeners[i].size(); k++) {
			fprintf(file, (radio_listeners[i][k] + "\n").c_str());
			numWrites++;
		}
	}

	fclose(file);
	ClientPrintAll(HUD_PRINTCONSOLE, UTIL_VarArgs("[Radio] Wrote %d listener ids to file.\n", numWrites));
}

void loadChannelListeners() {
	FILE* file = fopen(channel_listener_file, "r");

	if (!file) {
		string text = string("[Radio] Failed to open: ") + channel_listener_file + "\n";
		println(text);
		logln(text);
		return;
	}

	int channelList = -1;
	int loadedStates = 0;
	string line;
	while (cgetline(file, line)) {
		if (line.empty()) {
			continue;
		}

		if (line[0] == '\\') {
			channelList = atoi(line.substr(1, 2).c_str());
			if (channelList < 0) {
				channelList = -1;
			}
			if (channelList >= int(g_channels.size())) {
				channelList = 0;
			}
			continue;
		}

		PlayerState* state = new PlayerState();
		state->channel = channelList;
		g_player_states[line] = state;
		loadedStates++;
	}

	println(UTIL_VarArgs("[Radio] Loaded %d states from file", loadedStates));

	fclose(file);
}

map<string, int> g_sound_indexes; // maps file paths to sound indexes
map<int, string> g_index_sounds; // maps sound indexes to file paths
map<string, int> g_sentence_indexes; // maps sentence names to sentence indexes
string g_soundcache_folder = "svencoop/maps/soundcache/";

enum parse_modes {
	PARSE_NONE,
	PARSE_SOUNDS,
	PARSE_SENTENCES
};

void loadSoundCacheFile() {
	g_sound_indexes.clear();
	g_sentence_indexes.clear();

	string soundcache_path = g_soundcache_folder + STRING(gpGlobals->mapname) + ".txt";
	FILE* file = fopen(soundcache_path.c_str(), "r");
	int parseMode = PARSE_NONE;
	int idx = 0;

	if (!file) {
		println("[Radio] failed to open soundcache file: " + soundcache_path + "\n");
		logln("[Radio] failed to open soundcache file: " + soundcache_path + "\n");
		return;
	}

	string line;
	while (cgetline(file, line)) {
		if (parseMode == PARSE_NONE) {
			if (line.find("SOUNDLIST {") == 0) {
				parseMode = PARSE_SOUNDS;
				continue;
			}
			if (line.find("SENTENCELIST {") == 0) {
				parseMode = PARSE_SENTENCES;
				continue;
			}
		}
		else {
			if (line.find("}") == 0) {
				parseMode = PARSE_NONE;
				idx = 0;
				continue;
			}

			if (parseMode == PARSE_SOUNDS) {
				g_sound_indexes[line] = idx;
				g_index_sounds[idx] = line;
			}
			else if (parseMode == PARSE_SENTENCES) {
				vector<string> parts = splitString(line, " ");
				g_sentence_indexes["!" + parts[0]] = idx;
			}

			idx++;
		}
	}

	fclose(file);

	println("[Radio] Parsed %d sounds and %d sentences", (int)g_sound_indexes.size(), (int)g_sentence_indexes.size());
}

void MapInit(edict_t* pEdictList, int edictCount, int maxClients) {
	g_is_server_changing_levels = false;

	// Reset time-based vars
	for (auto const& item : g_player_states)
	{
		PlayerState& state = *item.second;
		state.lastInviteTime.clear();
		state.lastRequest = -9999;
		state.lastDjToggle = -9999;
		state.lastSongSkip = -9999;
	}

	for (int i = 0; i < g_channels.size(); i++) {
		g_channels[i].lastSongRequest = 0;
	}

	// fix for listen server with 1 player
	g_Scheduler.SetTimeout(updateSleepState, 1.0f);
	g_Scheduler.SetTimeout(loadSoundCacheFile, 1.0f);

	g_Scheduler.SetTimeout(start_network_threads, 1.0f); // wait until cvar is loaded

	RETURN_META(MRES_IGNORED);
}

void ClientJoin(edict_t* pEntity) {
	PlayerState& state = getPlayerState(pEntity);

	state.startedReliablePackets = false;
	state.reliablePacketsStart = g_engfuncs.pfnTime() + 10; // should be enough time to prevent overflow, usually
	state.activeMapMusic.clear();

	g_Scheduler.SetTimeout(updateSleepState, 1.0f);

	RETURN_META(MRES_IGNORED);
}

void ClientLeave(edict_t* plr) {
	if (g_is_server_changing_levels) {
		RETURN_META(MRES_IGNORED);
	}

	PlayerState& state = getPlayerState(plr);

	state.activeMapMusic.clear();
	if (state.channel >= 0) {
		if (g_channels[state.channel].currentDj == getPlayerUniqueId(plr)) {
			g_channels[state.channel].currentDj = "";
		}
	}

	updateSleepState();

	RETURN_META(MRES_IGNORED);
}

void radioThink() {
	for (int i = 0; i < g_channelCount->value; i++) {
		g_channels[i].think();
	}
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* plr = INDEXENT(i);

		if (!isValidPlayer(plr)) {
			continue;
		}

		PlayerState& state = getPlayerState(plr);

		if (state.channel >= 0 && state.showHud) {
			g_channels[state.channel].updateHud(plr, state);
		}
	}
}

// pick entities to emit voice data from (must be a player slot or else it doesn't always work)
void updateVoiceSlotIdx() {
	int old_radio_idx = g_radio_ent_idx;
	int old_voice_idx = g_voice_ent_idx;

	int found = 0;
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* plr = INDEXENT(i);

		if (!isValidPlayer(plr)) {
			if (found == 0) {
				g_radio_ent_idx = i - 1;
				found++;
			}
			else {
				g_voice_ent_idx = i - 1;
				found++;
				break;
			}
		}
	}

	if (found == 0) {
		g_radio_ent_idx = 0;
		g_voice_ent_idx = 1;
	}
	else if (found == 1) {
		g_voice_ent_idx = 0;
	}

	if (old_radio_idx != g_radio_ent_idx || old_voice_idx != g_voice_ent_idx) {
		edict_t* oldVoicePlr = INDEXENT(old_voice_idx);
		edict_t* oldRadioPlr = INDEXENT(old_radio_idx);

		if (!isValidPlayer(oldVoicePlr) && !isValidPlayer(oldRadioPlr)) {
			// no need to refresh. The old indexes are still pointing to null players.
			return;
		}

		// refresh voice labels
		println("Refresh voice labels");
		for (int i = 1; i <= gpGlobals->maxClients; i++) {
			edict_t* plr = INDEXENT(i);

			if (!isValidPlayer(plr)) {
				continue;
			}

			PlayerState& state = getPlayerState(plr);

			if (state.channel != -1 && g_channels[state.channel].activeSongs.size() > 0) {
				clientCommand(plr, "stopsound");
			}
		}
	}
}

void updateSleepState() {
	bool old_listeners = g_any_radio_listeners;
	g_any_radio_listeners = false;
	int numPlayers = 0;

	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* plr = INDEXENT(i);

		if (!isValidPlayer(plr)) {
			continue;
		}

		numPlayers += 1;
		PlayerState& state = getPlayerState(plr);

		// advertise to players in who are not listening to anything, or if their channel has nothing playing
		if (state.channel != -1) {
			g_any_radio_listeners = true;
		}
	}

	if (g_any_radio_listeners != old_listeners) {
		send_voice_server_message(string("Radio\\en\\100\\") + (g_any_radio_listeners ? ".resume_packets" : ".pause_packets"));
	}
}

void toggleMapMusic(edict_t* plr, bool enable) {
	if (!isValidPlayer(plr)) {
		return;
	}

	PlayerState& state = getPlayerState(plr);

	println("Toggle %d map musics for %s state %d", (int)state.activeMapMusic.size(), STRING(plr->v.netname), (int)enable);
	
	for (int i = 0; i < state.activeMapMusic.size(); i++) {
		if (enable) {
			state.activeMapMusic[i].resume(plr);
		}
		else {
			state.activeMapMusic[i].pause(plr);
		}
	}

	if (!enable) {
		clientCommand(plr, "mp3 stop");
	}

	if (state.activeMapMusic.size()) {
		if (enable) {
			ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] Unmuted map music.\n");
		}
		else {
			ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] Muted map music.\n");
		}
	}
}

void showConsoleHelp(edict_t* plr, bool showChatMessage) {
	bool isAdmin = AdminLevel(plr) >= ADMIN_YES;

	ClientPrint(plr, HUD_PRINTCONSOLE, "------------------------------ Radio Help ------------------------------\n\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "The radio speaks chat messages aloud and can play audio from youtube/soundcloud/etc.\n\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "To queue a video, open the console and type \"say \" followed by a link. Example:\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    say https://www.youtube.com/watch?v=b8HO6hba9ZE\n\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "To bypass the queue, use \"!\". Example:\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    say !https://www.youtube.com/watch?v=b8HO6hba9ZE\n\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "To play a video at a specific time, add a timecode after the link. Example:\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    say !https://www.youtube.com/watch?v=b8HO6hba9ZE 0:27\n\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "To hide your message from the chat, use \"~\". Example:\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    say ~You can hear me but you cannnot see me!\n\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "Is the audio stuttering?\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    Try typing \"stopsound\" in console. Voice playback often breaks after viewing a map cutscene.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    If that doesn\"t help, then check if you have any \"loss\" shown with \"net_graph 4\". If you do\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    then use the \".radio reliable\" command to send voice data on the reliable channel. This should\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    fix the audio cutting out but may cause desyncs or \"reliable channel overflow\".\n\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "Is the audio too loud/quiet?\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    You can adjust voice volume with \"voice_scale\" in console. Type stopsound to apply your change.\n\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "Commands:\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio                    open the radio menu.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio block/unblock      block/unblock radio invites/requests.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio lang x             set your text-to-speech language.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio langs              list valid text-to-speech languages.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio list               show who\"s listening.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio name <new_name>    rename the channel.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio pitch <10-200>     set your text-to-speech pitch.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio reliable           use the reliable channel to receive audio.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio stop               stop currently playing videos.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio stop first         stop all but the last video.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio stop last          stop all but the first video.\n");
	ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio stop speak         stop currently playing speech.\n");

	if (isAdmin) {
		ClientPrint(plr, HUD_PRINTCONSOLE, "\nAdmin commands:\n");
		ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio encoder <bitrate>  set opus encoder bitrate (default is 32000 bps).\n");
		ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio pause/resume       stop/continue processing audio packets.\n");
		ClientPrint(plr, HUD_PRINTCONSOLE, "    .radio stop global        stop currently playing speech and videos in all channels.\n");
	}

	ClientPrint(plr, HUD_PRINTCONSOLE, "\n------------------------------------------------------------------------\n");

	if (showChatMessage) {
		ClientPrint(plr, HUD_PRINTTALK, "[Radio] Help info sent to your console.\n");
	}
}

bool langsSort(string a, string b) {
	return g_langs[a] < g_langs[b];
}

bool doCommand(edict_t* plr) {
	bool isAdmin = AdminLevel(plr) >= ADMIN_YES;
	int playerid = g_engfuncs.pfnGetPlayerUserId(plr);
	PlayerState& state = getPlayerState(plr);
	g_args = CommandArgs();
	CommandArgs& args = g_args;
	args.loadArgs();

	string lowerArg = toLowerCase(args.ArgV(0));

	if (args.ArgC() > 0 && lowerArg == ".radio") {
		if (args.ArgC() == 1) {
			bool isEnabled = state.channel >= 0;

			if (isEnabled) {
				openMenuRadio(playerid);
			}
			else {
				if ((int)g_channelCount->value == 1) {
					joinRadioChannel(plr, 0);
					openMenuRadio(playerid);
				}
				else {
					openMenuChannelSelect(playerid);
				}
			}
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "hud") {
			state.showHud = !state.showHud;

			if (args.ArgC() > 2) {
				state.showHud = atoi(args.ArgV(2).c_str()) != 0;
			}

			ClientPrint(plr, HUD_PRINTTALK, UTIL_VarArgs("[Radio] HUD %s.\n", state.showHud ? "enabled" : "disabled"));
		}
		else if (args.ArgC() > 2 && args.ArgV(1) == "encoder") {
			if (!isAdmin) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Admins only.\n");
				return true;
			}
			int newRate = atoi(args.ArgV(2).c_str());
			string encoderCmd = "settings " + newRate;
			send_voice_server_message("Radio\\en\\100\\.encoder " + encoderCmd);
			ClientPrintAll(HUD_PRINTTALK, UTIL_VarArgs("[Radio] %s set audio bitrate to %d bps.\n", STRING(plr->v.netname), newRate));
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "pause") {
			if (!isAdmin) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Admins only.\n");
				return true;
			}
			if (g_admin_pause_packets) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Audio is already paused.\n");
				return true;
			}

			g_admin_pause_packets = true;
			ClientPrintAll(HUD_PRINTTALK, UTIL_VarArgs("[Radio] Audio paused by %s.\n", STRING(plr->v.netname)));
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "reconnect") {
			if (!isAdmin) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Admins only.\n");
				return true;
			}
			g_plugin_exiting = true;
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] Restarting network threads.\n");
			g_Scheduler.SetTimeout(stop_network_threads, 2.0f); // wait a while so main thread doesn't hang when joining threads
			g_Scheduler.SetTimeout(start_network_threads, 3.0f);			
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "disconnect") {
			if (!isAdmin) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Admins only.\n");
				return true;
			}
			g_plugin_exiting = true;
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] Disconnecting from radio server.\n");
			g_Scheduler.SetTimeout(stop_network_threads, 2.0f); // wait a while so main thread doesn't hang when joining threads
		}
		else if (args.ArgC() > 1 && (args.ArgV(1) == "unpause" || args.ArgV(1) == "resume")) {
			if (!isAdmin) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Admins only.\n");
				return true;
			}
			if (!g_admin_pause_packets) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Audio is already resumed.\n");
				return true;
			}

			g_admin_pause_packets = false;
			ClientPrintAll(HUD_PRINTTALK, UTIL_VarArgs("[Radio] Audio resumed by %s.\n", STRING(plr->v.netname)));
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "stop") {
			string arg = args.ArgV(2);

			float delta = gpGlobals->time - state.lastLaggyCmd;
			if (delta < 1 && delta >= 0) {
				ClientPrint(plr, HUD_PRINTTALK, "Wait a second before using that command.\n");
				return true;
			}
			state.lastLaggyCmd = gpGlobals->time;

			if (state.channel == -1) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] You must be in a radio channel to use this command.\n");
				return true;
			}

			Channel& chan = g_channels[state.channel];

			if (arg == "") {
				chan.stopMusic(plr, -1, false);
			}
			else if (arg == "first") {
				chan.stopMusic(plr, chan.activeSongs.size() - 1, false);
			}
			else if (arg == "last") {
				chan.stopMusic(plr, 0, false);
			}
			else if (arg == "clear") {
				chan.stopMusic(plr, -1, true);
			}
			else if (arg == "speak") {
				send_voice_server_message("Radio\\en\\100\\.radio stop speak");
			}
			else if (arg == "global") {
				if (!isAdmin) {
					ClientPrint(plr, HUD_PRINTTALK, "[Radio] Admins only.\n");
					return true;
				}
				send_voice_server_message("Radio\\en\\100\\.radio stop global");
			}

			return true;
		}
		else if (args.ArgC() > 2 && args.ArgV(1) == "name") {
			string newName = args.ArgV(2);

			float delta = gpGlobals->time - state.lastLaggyCmd;
			if (delta < 1 && delta >= 0) {
				ClientPrint(plr, HUD_PRINTTALK, "Wait a second before using that command.\n");
				return true;
			}
			state.lastLaggyCmd = gpGlobals->time;

			if (state.channel == -1) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] You must be in a radio channel to use this command.\n");
				return true;
			}

			Channel& chan = g_channels[state.channel];
			chan.rename(plr, newName);

			return true;
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "reliable") {
			state.reliablePackets = !state.reliablePackets;

			if (args.ArgC() > 2) {
				state.reliablePackets = atoi(args.ArgV(2).c_str()) != 0;
				state.reliablePacketsStart = g_engfuncs.pfnTime();
			}

			ClientPrint(plr, HUD_PRINTTALK, UTIL_VarArgs("[Radio] Reliable packets %s.\n",state.reliablePackets ? "enabled" : "disabled"));
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "list") {
			float delta = gpGlobals->time - state.lastLaggyCmd;
			if (delta < 1 && delta >= 0) {
				ClientPrint(plr, HUD_PRINTTALK, "Wait a second before using that command.\n");
				return true;
			}
			state.lastLaggyCmd = gpGlobals->time;

			for (int i = 0; i < g_channelCount->value; i++) {
				Channel& chan = g_channels[i];
				vector<edict_t*> listeners = chan.getChannelListeners();

				string title = chan.name;
				edict_t* dj = chan.getDj();

				if (dj) {
					title += "  (DJ: " + string(STRING(dj->v.netname)) + ")";
				}

				ClientPrint(plr, HUD_PRINTCONSOLE, ("\n\n" + title + "\n------------------").c_str());
				for (int k = 0; k < listeners.size(); k++) {
					int pos = (k + 1);
					string spos = to_string(pos);
					if (pos < 10) {
						spos = " " + spos;
					}

					PlayerState& lstate = getPlayerState(listeners[k]);
					const char * mute = "";
					if (lstate.muteMode == MUTE_TTS) {
						mute = "(Mute: speech)";
					}
					else if (lstate.muteMode == MUTE_VIDEOS) {
						mute = "(Mute: videos)";
					}

					string tts = UTIL_VarArgs("(TTS: %s %d)", lstate.lang.c_str(), lstate.pitch);

					ClientPrint(plr, HUD_PRINTCONSOLE, UTIL_VarArgs("\n%s) %s %s %s", spos.c_str(), STRING(listeners[k]->v.netname), tts.c_str(), mute));
				}

				if (listeners.size() == 0) {
					ClientPrint(plr, HUD_PRINTCONSOLE, "\n(empty)");
				}
			}

			ClientPrint(plr, HUD_PRINTCONSOLE, "\n\n");
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "help") {
			showConsoleHelp(plr, !args.isConsoleCmd);
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "block") {
			state.blockInvites = true;
			state.requestsAllowed = false;
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] Blocked radio invites/requests.\n");
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "unblock") {
			state.blockInvites = false;
			state.requestsAllowed = true;
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] Unblocked radio invites/requests.\n");
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "lang") {
			string code = toLowerCase(args.ArgV(2));

			if (g_langs.find(code) != g_langs.end()) {
				state.lang = code;
				ClientPrint(plr, HUD_PRINTTALK, (string("[Radio] TTS language set to ") + g_langs[code] + ".\n").c_str());
			}
			else {
				ClientPrint(plr, HUD_PRINTTALK, ("[MicBot] Invalid language code \"" + code + "\". Type \".radio langs\" for a list of valid codes.\n").c_str());
			}

			return true; // hide from chat relay
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "langs") {
			float delta = gpGlobals->time - state.lastLaggyCmd;
			if (delta < 1 && delta >= 0) {
				ClientPrint(plr, HUD_PRINTTALK, "Wait a second before using that command.\n");
				return true;
			}
			state.lastLaggyCmd = gpGlobals->time;

			ClientPrint(plr, HUD_PRINTTALK, "[Radio] TTS language codes sent to your console.\n");

			vector<string> langKeys;
			for (auto const& item : g_langs) {
				langKeys.push_back(item.first);
			}
			std::sort(langKeys.begin(), langKeys.end(), langsSort);

			ClientPrint(plr, HUD_PRINTCONSOLE, "Valid language codes:\n");
			for (int i = 0; i < g_langs.size(); i++) {
				ClientPrint(plr, HUD_PRINTCONSOLE, ("    " + langKeys[i] + " = " + g_langs[langKeys[i]] + "\n").c_str());
			}

			return true; // hide from chat relay
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "pitch") {
			int pitch = atoi(args.ArgV(2).c_str());

			if (pitch < 10) {
				pitch = 10;
			}
			else if (pitch > 200) {
				pitch = 200;
			}

			state.pitch = pitch;

			ClientPrint(plr, HUD_PRINTTALK, UTIL_VarArgs("[Radio] TTS pitch set to %d.\n", pitch));

			return true; // hide from chat relay
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "debug") {
			state.isDebugging = !state.isDebugging;

			if (state.isDebugging) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Debug mode ON.\n");
			}
			else {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Debug mode OFF.\n");
			}
		}
		else if (args.ArgC() > 1 && args.ArgV(1) == "mapmusic") {
			state.isMapMusicDebug = !state.isMapMusicDebug;

			if (state.isMapMusicDebug) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Map music debug mode ON.\n");
			}
			else {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] Map music debug OFF.\n");
			}
		}

		return true;
	}
	else if (lowerArg.find("https://") <= 1 || lowerArg.find("http://") <= 1) {
		if (state.channel != -1) {
			lowerArg = trimSpaces(lowerArg);

			bool isHiddenChat = lowerArg.find("https://") == 1 || lowerArg.find("http://") == 1;

			Channel& chan = g_channels[state.channel];
			bool canDj = chan.canDj(plr);

			string url = args.ArgV(0);
			bool playNow = url[0] == '!';
			if (isHiddenChat)
				url = url.substr(1);

			Song song;
			song.path = url;
			song.loadState = SONG_UNLOADED;
			song.id = g_song_id;
			song.requester = STRING(plr->v.netname);
			song.args = args.ArgV(1);

			g_song_id += 1;

			if (g_admin_pause_packets) {
				ClientPrint(plr, HUD_PRINTTALK, "[Radio] The plugin is temporarily disabled to prevent lag.\n");
				return true;
			}

			if (playNow && int(chan.activeSongs.size()) >= chan.maxStreams) {
				ClientPrint(plr, HUD_PRINTTALK, UTIL_VarArgs("[Radio] This channel can't play more than %d videos at the same time.\n", chan.maxStreams));
				return true;
			}

			if (!canDj) {
				if (int(chan.queue.size()) >= g_maxQueue->value) {
					ClientPrint(plr, HUD_PRINTTALK, "[Radio] Can't request now. The queue is full.\n");
				}
				else if (!state.shouldRequestCooldown(plr)) {
					if (chan.requestSong(plr, song)) {
						state.lastRequest = gpGlobals->time;
					}
				}
			}
			else {
				if (playNow) {
					chan.playSong(song);
				}
				else {
					chan.queueSong(plr, song);
				}
			}

			return isHiddenChat;
		}
	}
	else if (!args.isConsoleCmd && lowerArg.length() > 0) {
		if (lowerArg[0] == '~') {
			if (g_any_radio_listeners && lowerArg.find("https://") != 0 && lowerArg.find("http://") != 0) {
				// speak the message
				send_voice_server_message(UTIL_VarArgs("%s\\%s\\%d\\%s", STRING(plr->v.netname), state.lang.c_str(), state.pitch, args.getFullCommand().c_str()));
			}

			ClientPrintAll(HUD_PRINTCONSOLE, (string("[Radio][TTS] ") + STRING(plr->v.netname) + ": " + args.getFullCommand() + "\n").c_str());
			return true;
		}
	}

	return false;
}
