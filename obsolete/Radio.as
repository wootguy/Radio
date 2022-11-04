#include "../inc/RelaySay"
#include "Channel"
#include "menus"
#include "util"
#include "target_cdaudio_radio"
#include "ambient_music_radio"
#include "FakeMic"
#include "TextToSpeech"

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

const string SONG_FILE_PATH = "scripts/plugins/Radio/songs.txt";
const string MUSIC_PACK_PATH = "scripts/plugins/Radio/music_packs.txt";
const int MAX_SERVER_ACTIVE_SONGS = 16;
const int SONG_REQUEST_TIMEOUT = 20;
const int SONG_START_TIMEOUT = 20; // max time to wait before cancelling a song that never started

CCVar@ g_inviteCooldown;
CCVar@ g_requestCooldown;
CCVar@ g_djSwapCooldown;
CCVar@ g_skipSongCooldown;
CCVar@ g_djReserveTime;
CCVar@ g_djIdleTime;
CCVar@ g_maxQueue;
CCVar@ g_channelCount;
CCVar@ g_maxPlayers;
CCVar@ g_maxPlayers2;

CClientCommand _radio("radio", "radio commands", @consoleCmd );
CClientCommand _radio2("radiodbg", "radio commands", @consoleCmd );

dictionary g_player_states;
array<Channel> g_channels;
string channel_listener_file = "scripts/plugins/store/radio_listeners.txt";

array<int> g_player_lag_status;
uint g_song_id = 1;
bool g_any_radio_listeners = false;
bool g_is_scripted_map = false;


// Menus need to be defined globally when the plugin is loaded or else paging doesn't work.
// Each player needs their own menu or else paging breaks when someone else opens the menu.
// These also need to be modified directly (not via a local var reference).
array<CTextMenu@> g_menus = {
	null, null, null, null, null, null, null, null,
	null, null, null, null, null, null, null, null,
	null, null, null, null, null, null, null, null,
	null, null, null, null, null, null, null, null,
	null
};


enum MUTE_MODE {
	MUTE_NONE,
	MUTE_TTS,
	MUTE_VIDEOS,
	MUTE_MODES
}

class PlayerState {
	int channel = -1;
	dictionary lastInviteTime; // for invite cooldowns per player and for \everyone
	float lastRequest; // for request cooldowns
	float lastDjToggle; // for cooldown
	float lastSongSkip; // for cooldown
	float lastLaggyCmd; // for cooldown
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
	
	bool shouldInviteCooldown(CBasePlayer@ plr, string id) {
		float inviteTime = -9999;
		if (lastInviteTime.exists(id)) {
			lastInviteTime.get(id, inviteTime);
		}
	
		if (int(id.Find("\\")) != -1) {
			id = id.Replace("\\", "");
		} else {
			CBasePlayer@ target = getPlayerByUniqueId(id);
			if (target !is null) {
				id = target.pev.netname;
			}
		}
		
		return shouldCooldownGeneric(plr, inviteTime, g_inviteCooldown.GetInt(), "inviting " + id + " again");
	}
	
	bool shouldRequestCooldown(CBasePlayer@ plr) {
		return shouldCooldownGeneric(plr, lastRequest, g_djSwapCooldown.GetInt(), "requesting another song");
	}
	
	bool shouldDjToggleCooldown(CBasePlayer@ plr) {
		return shouldCooldownGeneric(plr, lastDjToggle, g_djSwapCooldown.GetInt(), "toggling DJ mode again");
	}
	
	bool shouldSongSkipCooldown(CBasePlayer@ plr) {	
		return shouldCooldownGeneric(plr, lastSongSkip, g_skipSongCooldown.GetInt(), "skipping another song");
	}
	
	bool shouldCooldownGeneric(CBasePlayer@ plr, float lastActionTime, int cooldownTime, string actionDesc) {
		float delta = g_Engine.time - lastActionTime;
		if (delta < cooldownTime) {			
			int waitTime = int((cooldownTime - delta) + 0.99f);
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Wait " + waitTime + " seconds before " + actionDesc + ".\n");
			return true;
		}
		
		return false;
	}
	
	bool isRadioMusicPlaying() {
		return channel >= 0 and g_channels[channel].activeSongs.size() > 0;
	}
}

enum SONG_LOAD_STATES {
	SONG_UNLOADED,
	SONG_LOADING,
	SONG_LOADED,
	SONG_FAILED,
	SONG_FINISHED // needed for videos that have no duration info
};

class Song {
	string title;
	string artist;
	string path; // file path or youtube url
	uint lengthMillis; // duration in milliseconds
	
	int offset;
	int loadState = SONG_LOADED;
	uint id = 0; // used to relate messages from the voice server to a song in some channel's queue
	string requester;
	DateTime startTime;
	bool isPlaying = false;
	bool messageSent = false; // was chat message sent about this song being added
	bool noRestart = false; // failsafe for infinite video restarting
	string args; // playback args (time offset)
	float loadTime; // time that song started waiting to start after loading
	
	string getClippedName(int length, bool ascii) {
		string name = getName(ascii);
		
		if (int(name.Length()) > length) {
			int sz = (length-4) / 2;
			return name.SubString(0,sz) + " .. " + name.SubString(name.Length()-sz);
		}
		
		return name;
	}
	
	string getName(bool ascii) const {
		string name = artist + " - " + title;
		if (artist.Length() == 0) {
			name = title.Length() > 0 ? title : path;
		}
		
		if (!ascii) {
			return name;
		}
		
		string ascii_name = "";
		
		for (uint i = 0; i < name.Length(); i++) {
			if (name[i] >= 32 && name[i] <= 126) {
				ascii_name += name[i];
			}
		}
		
		if (ascii_name.Length() == 0) {
			ascii_name = "?";
		}
		
		return ascii_name;
	}
	
	int getTimeLeft() {
		int songLen = ((lengthMillis + 999) / 1000) - (offset/1000);
		return songLen - getTimePassed();
	}
	
	int getTimePassed() {
		if (loadState != SONG_LOADED) {
			startTime = DateTime();
		}
		int diff = int(TimeDifference(DateTime(), startTime).GetTimeDifference());
		return diff;
	}
	
	bool isFinished() {
		return loadState == SONG_FAILED or (loadState == SONG_LOADED and getTimeLeft() <= 0 and lengthMillis != 0) or loadState == SONG_FINISHED;
	}
}

enum LAG_STATES {
	LAG_NONE,
	LAG_SEVERE_MSG,
	LAG_JOINING
}


void PluginInit() {
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @ClientJoin);
	g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @ClientLeave);
	g_Hooks.RegisterHook(Hooks::Player::ClientSay, @ClientSay);
	g_Hooks.RegisterHook(Hooks::Game::MapChange, @MapChange);
	g_Hooks.RegisterHook(Hooks::Player::PlayerPostThink, @PlayerPostThink );
	
	@g_inviteCooldown = CCVar("inviteCooldown", 600, "Radio invite cooldown", ConCommandFlag::AdminOnly);
	@g_requestCooldown = CCVar("requestCooldown", 300, "Song request cooldown", ConCommandFlag::AdminOnly);
	@g_djSwapCooldown = CCVar("djSwapCooldown", 5, "DJ mode toggle cooldown", ConCommandFlag::AdminOnly);
	@g_skipSongCooldown = CCVar("skipSongCooldown", 10, "Audio stop cooldown", ConCommandFlag::AdminOnly);
	@g_djReserveTime = CCVar("djReserveTime", 240, "Time to reserve DJ slots after level change", ConCommandFlag::AdminOnly);
	@g_djIdleTime = CCVar("djIdleTime", 180, "Time a DJ can be idle before being ejected", ConCommandFlag::AdminOnly);
	@g_maxQueue = CCVar("maxQueue", 8, "Max songs that can be queued", ConCommandFlag::AdminOnly);
	@g_channelCount = CCVar("channelCount", 1, "Number of available channels", ConCommandFlag::AdminOnly);
	@g_maxPlayers = CCVar("maxPlayers", 28, "Max players before audio is disabled to prevent lag on normal maps", ConCommandFlag::AdminOnly);
	@g_maxPlayers2 = CCVar("maxPlayers2", 24, "Max players before audio is disabled to prevent lag on scripted maps", ConCommandFlag::AdminOnly);
	
	g_channels.resize(g_channelCount.GetInt());
	
	for (uint i = 0; i < g_channels.size(); i++) {
		g_channels[i].name = "Channel " + (i+1);
		g_channels[i].id = i;
		g_channels[i].maxStreams = 3;
		
		if (i == 0) {
			g_channels[i].spamMode = true;
			g_channels[i].maxStreams = 6;
		}
	}
	
	if (g_channels.size() == 1) {
		g_channels[0].name = "Radio";
		g_channels[0].spamMode = false;
		g_channels[0].maxStreams = 12;
	}
	
	g_Scheduler.SetInterval("radioThink", 0.5f, -1);
	g_Scheduler.SetInterval("writeChannelListeners", 60*10, -1);
	g_Scheduler.SetInterval("updateVoiceSlotIdx", 3, -1);
	
	load_samples();
	play_samples();
	
	g_player_lag_status.resize(33);
	
	send_voice_server_message("Radio\\en\\100\\.radio stop global");
	send_voice_server_message("Radio\\en\\100\\.pause_packets");
	
	loadChannelListeners();
	updateSleepState();
}

void PluginExit() {
	writeChannelListeners();
}

void writeChannelListeners() {
	File@ file = g_FileSystem.OpenFile( channel_listener_file, OpenFile::WRITE );
	
	if (file is null or !file.IsOpen()) {
		string text = "[Radio] Failed to open: " + channel_listener_file + "\n";
		println(text);
		g_Log.PrintF(text);
		return;
	}
	
	array<array<string>> radio_listeners;
	for (uint i = 0; i < g_channels.size(); i++) {
		radio_listeners.insertLast(array<string>());
	}
	int numWrites = 0;
	
	array<string>@ states = g_player_states.getKeys();
	for (uint i = 0; i < states.length(); i++)
	{
		PlayerState@ state = cast< PlayerState@ >(g_player_states[states[i]]);
		if (state.channel >= 0 and state.channel < int(g_channels.size())) {
			radio_listeners[state.channel].insertLast(states[i]);
		}
	}
	
	for (uint i = 0; i < g_channels.size(); i++) {
		file.Write("\\" + i + "\\\n");
		
		for (uint k = 0; k < radio_listeners[i].size(); k++) {
			file.Write(radio_listeners[i][k] + "\n");
			numWrites++;
		}
	}
	
	file.Close();
	g_PlayerFuncs.ClientPrintAll(HUD_PRINTCONSOLE, "[Radio] Wrote " + numWrites + " listener ids to file.\n");
}

void loadChannelListeners() {
	File@ file = g_FileSystem.OpenFile( channel_listener_file, OpenFile::READ );
	
	if (file is null or !file.IsOpen()) {
		string text = "[Radio] Failed to open: " + channel_listener_file + "\n";
		println(text);
		g_Log.PrintF(text);
		return;
	}
	
	int channelList = -1;
	int loadedStates = 0;
	while (!file.EOFReached()) {
		string line;
		file.ReadLine(line);
		
		if (line.IsEmpty()) {
			continue;
		}
		
		if (line[0] == '\\') {
			channelList = atoi(line.SubString(1,2));
			if (channelList < 0) {
				channelList = -1;
			}
			if (channelList >= int(g_channels.size())) {
				channelList = 0;
			}
			continue;
		}
		
		PlayerState state;
		state.channel = channelList;
		g_player_states[line] = state;
		loadedStates++;
	}
	
	println("[Radio] Loaded " + loadedStates + " states from file");
	
	file.Close();
}

void MapInit() {
	// Reset time-based vars
	array<string>@ states = g_player_states.getKeys();
	for (uint i = 0; i < states.length(); i++)
	{
		PlayerState@ state = cast< PlayerState@ >(g_player_states[states[i]]);
		state.lastInviteTime.clear();
		state.lastRequest = -9999;
		state.lastDjToggle = -9999;
		state.lastSongSkip = -9999;
	}
	
	g_is_scripted_map = false;
	
	for (uint i = 0; i < g_channels.size(); i++) {
		g_channels[i].lastSongRequest = 0;
	}
	
	File@ file = g_FileSystem.OpenFile( voice_server_file, OpenFile::APPEND );
	
	if (!file.IsOpen()) {
		string text = "[Radio] Failed to open: " + voice_server_file + "\n";
		println(text);
		g_Log.PrintF(text);
		return;
	}
	
	file.Write("truncate_radio_file\n");
	file.Close();
}

// for quick plugin reloading (comment out music #include first)
//namespace AmbientMusicRadio { void toggleMapMusic(CBasePlayer@ plr, bool toggleOn) {} } 

int g_replaced_cdaudio = 0;
int g_replaced_music = 0;
void MapActivate() {
	g_CustomEntityFuncs.RegisterCustomEntity( "target_cdaudio_radio", "target_cdaudio_radio" );
	g_CustomEntityFuncs.RegisterCustomEntity( "AmbientMusicRadio::ambient_music_radio", "ambient_music_radio" );
	
	g_replaced_cdaudio = 0;
	g_replaced_music = 0;
	
	CBaseEntity@ cdaudio = null;
	do {
		@cdaudio = g_EntityFuncs.FindEntityByClassname(cdaudio, "target_cdaudio"); 

		if (cdaudio !is null)
		{
			dictionary keys;
			keys["origin"] = cdaudio.pev.origin.ToString();
			keys["targetname"] = string(cdaudio.pev.targetname);
			keys["health"] =  "" + cdaudio.pev.health;
			CBaseEntity@ newent = g_EntityFuncs.CreateEntity("target_cdaudio_radio", keys, true);
		
			g_EntityFuncs.Remove(cdaudio);
			g_replaced_cdaudio++;
		}
	} while (cdaudio !is null);
	
	println("[Radio] Replaced " + g_replaced_cdaudio + " trigger_cdaudio entities with trigger_cdaudio_radio");
	
	CBaseEntity@ music = null;
	do {
		@music = g_EntityFuncs.FindEntityByClassname(music, "ambient_music"); 

		if (music !is null)
		{
			dictionary keys;
			keys["origin"] = music.pev.origin.ToString();
			keys["targetname"] = string(music.pev.targetname);
			keys["message"] =  "" + music.pev.message;
			keys["spawnflags"] =  "" + music.pev.spawnflags;
			//keys["volume"] =  "" + music.pev.volume; // Can't do this, so just assuming it's always max volume
			CBaseEntity@ newent = g_EntityFuncs.CreateEntity("ambient_music_radio", keys, true);
		
			g_EntityFuncs.Remove(music);
			g_replaced_music++;
		}
	} while (music !is null);
	
	println("[Radio] Replaced " + g_replaced_music + " ambient_music entities with ambient_music_radio");
}

HookReturnCode MapChange() {	
	for (uint i = 0; i < 33; i++) {
		g_player_lag_status[i] = LAG_JOINING;
	}

	return HOOK_CONTINUE;
}

HookReturnCode ClientJoin(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	string id = getPlayerUniqueId(plr);

	state.playAfterFullyLoaded = true;
	state.startedReliablePackets = false;
	state.reliablePacketsStart = 999999;
	
	updateSleepState();
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientLeave(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	
	if (state.channel >= 0) {
		if (g_channels[state.channel].currentDj == getPlayerUniqueId(plr)) {
			g_channels[state.channel].currentDj = "";
		}
	}
	
	updateSleepState();
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientSay( SayParameters@ pParams ) {
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	
	if (!pParams.ShouldHide and doCommand(plr, args, false)) {
		pParams.ShouldHide = true;
	}
	
	return HOOK_CONTINUE;
}

void radioThink() {	
	loadCrossPluginLoadState();
	
	for (uint i = 0; i < g_channels.size(); i++) {
		g_channels[i].think();
	}
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		
		if (state.playAfterFullyLoaded and g_player_lag_status[plr.entindex()] == LAG_NONE) {
			println("Toggline map music for fully loaded player: " + plr.pev.netname);
			state.playAfterFullyLoaded = false;
			state.reliablePacketsStart = g_EngineFuncs.Time() + 10;
			AmbientMusicRadio::toggleMapMusic(plr, !(state.isRadioMusicPlaying()));
		}

		if (state.channel >= 0 and state.showHud) {
			g_channels[state.channel].updateHud(plr, state);
		}
		
		if (!g_is_scripted_map) {
			CBaseEntity@ heldWep = plr.m_hActiveItem;
			
			if (heldWep !is null and g_CustomEntityFuncs.IsCustomEntity(heldWep.pev.classname)) {
				g_is_scripted_map = true;
				updateSleepState();
			}
		}
	}
}

void loadCrossPluginLoadState() {
	CBaseEntity@ afkEnt = g_EntityFuncs.FindEntityByTargetname(null, "PlayerStatusPlugin");
	
	if (afkEnt is null) {
		return;
	}
	
	CustomKeyvalues@ customKeys = afkEnt.GetCustomKeyvalues();
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CustomKeyvalue key = customKeys.GetKeyvalue("$i_state" + i);
		if (key.Exists()) {
			g_player_lag_status[i] = key.GetInteger();
		}
	}
}

// pick entities to emit voice data from (must be a player slot or else it doesn't always work)
void updateVoiceSlotIdx() {
	int old_radio_idx = g_radio_ent_idx;
	int old_voice_idx = g_voice_ent_idx;
	
	int found = 0;
	for ( int i = g_Engine.maxClients; i > 0; i++ ) {
		CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (p is null) {
			if (found == 0) {
				g_radio_ent_idx = i-1;
				found++;
			} else {
				g_voice_ent_idx = i-1;
				found++;
				break;
			}
		}
	}
	
	if (found == 0) {
		g_radio_ent_idx = 0;
		g_voice_ent_idx = 1;
	} else if (found == 1) {
		g_voice_ent_idx = 0;
	}

	if (old_radio_idx != g_radio_ent_idx or old_voice_idx != g_voice_ent_idx) {
		CBasePlayer@ oldVoicePlr = g_PlayerFuncs.FindPlayerByIndex(old_voice_idx);
		CBasePlayer@ oldRadioPlr = g_PlayerFuncs.FindPlayerByIndex(old_radio_idx);
		
		if (oldVoicePlr is null and oldRadioPlr is null) {
			// no need to refresh. The old indexes are still pointing to null players.
			return;
		}
	
		// refresh voice labels
		println("Refresh voice labels");
		for ( int i = 1; i <= g_Engine.maxClients; i++ )
		{
			CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (plr is null or !plr.IsConnected()) {
				continue;
			}
			
			PlayerState@ state = getPlayerState(plr);
			
			if (state.channel != -1 and g_channels[state.channel].activeSongs.size() > 0) {
				clientCommand(plr, "stopsound");
			}
		}
	}
}

void updateSleepState() {
	bool old_listeners = g_any_radio_listeners;
	g_any_radio_listeners = false;
	int numPlayers = 0;
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (p is null or !p.IsConnected()) {
			continue;
		}
		
		numPlayers += 1;
		PlayerState@ state = getPlayerState(p);
		
		// advertise to players in who are not listening to anything, or if their channel has nothing playing
		if (state.channel != -1) {
			g_any_radio_listeners = true;
		}
	}
	
	int playerLimit = g_is_scripted_map ? g_maxPlayers2.GetInt() : g_maxPlayers.GetInt();
	
	bool should_pause_radio = numPlayers >= playerLimit;
	if (should_pause_radio != g_lag_pause_packets) {
		if (should_pause_radio) {
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTNOTIFY, "[Radio] Plugin disabled to prevent lag while player count is high.\n");
		} else {
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTNOTIFY, "[Radio] Plugin re-enabled. Player count is low enough that the server shouldn't lag.\n");
		}
	}
	g_lag_pause_packets = should_pause_radio;
	
	
	if (g_any_radio_listeners != old_listeners) {
		send_voice_server_message("Radio\\en\\100\\" + (g_any_radio_listeners ? ".resume_packets" : ".pause_packets"));
	}
}

void showConsoleHelp(CBasePlayer@ plr, bool showChatMessage) {
	bool isAdmin = g_PlayerFuncs.AdminLevel(plr) >= ADMIN_YES;
	
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '------------------------------ Radio Help ------------------------------\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'The radio speaks chat messages aloud and can play audio from youtube/soundcloud/etc.\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'To queue a video, open the console and type "say " followed by a link. Example:\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    say https://www.youtube.com/watch?v=b8HO6hba9ZE\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'To bypass the queue, use "!". Example:\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    say !https://www.youtube.com/watch?v=b8HO6hba9ZE\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'To play a video at a specific time, add a timecode after the link. Example:\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    say !https://www.youtube.com/watch?v=b8HO6hba9ZE 0:27\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'To hide your message from the chat, use "~". Example:\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    say ~You can hear me but you cannnot see me!\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Is the audio stuttering?\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Try typing "stopsound" in console. Voice playback often breaks after viewing a map cutscene.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    If that doesn\'t help, then check if you have any "loss" shown with "net_graph 4". If you do\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    then use the ".radio reliable" command to send voice data on the reliable channel. This should\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    fix the audio cutting out but may cause desyncs or "reliable channel overflow".\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Is the audio too loud/quiet?\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    You can adjust voice volume with "voice_scale" in console. Type stopsound to apply your change.\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Commands:\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio                    open the radio menu.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio block/unblock      block/unblock radio invites/requests.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio lang x             set your text-to-speech language.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio langs              list valid text-to-speech languages.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio list               show who\'s listening.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio name <new_name>    rename the channel.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio pitch <10-200>     set your text-to-speech pitch.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio reliable           use the reliable channel to receive audio.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio stop               stop currently playing videos.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio stop first         stop all but the last video.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio stop last          stop all but the first video.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio stop speak         stop currently playing speech.\n');	
	
	if (isAdmin) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nAdmin commands:\n');
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio encoder <bitrate>  set opus encoder bitrate (default is 32000 bps).\n');
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio pause/resume       stop/continue processing audio packets.\n');
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    .radio stop global        stop currently playing speech and videos in all channels.\n');
	}
	
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\n------------------------------------------------------------------------\n');

	if (showChatMessage) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, '[Radio] Help info sent to your console.\n');
	}
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args, bool inConsole) {
	bool isAdmin = g_PlayerFuncs.AdminLevel(plr) >= ADMIN_YES;
	PlayerState@ state = getPlayerState(plr);
	
	if (args.ArgC() > 0 && args[0] == ".radiodbg") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] replaced " + g_replaced_cdaudio + " cd audios.\n");
		return true;
	}
	
	string lowerArg = args[0].ToLowercase();
	
	if (args.ArgC() > 0 && args[0] == ".radio") {
	
		if (args.ArgC() == 1) {
			bool isEnabled = state.channel >= 0;
	
			if (isEnabled) {
				openMenuRadio(EHandle(plr));
			} else {
				if (g_channelCount.GetInt() == 1) {
					joinRadioChannel(plr, 0);
					openMenuRadio(EHandle(plr));
				} else {
					openMenuChannelSelect(EHandle(plr));
				}
				
			}
		}
		else if (args.ArgC() > 1 and args[1] == "hud") {
			state.showHud = !state.showHud;
			
			if (args.ArgC() > 2) {
				state.showHud = atoi(args[2]) != 0;
			}
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] HUD " + (state.showHud ? "enabled" : "disabled") + ".\n");
		}
		else if (args.ArgC() > 2 and args[1] == "encoder") {
			if (!isAdmin) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Admins only.\n");
				return true;
			}
			int newRate = atoi(args[2]);
			string encoderCmd = "settings " + newRate;
			send_voice_server_message("Radio\\en\\100\\.encoder " + encoderCmd);
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTTALK, "[Radio] " + plr.pev.netname + " set audio bitrate to " + newRate + " bps.\n");
		}
		else if (args.ArgC() > 1 and args[1] == "pause") {
			if (!isAdmin) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Admins only.\n");
				return true;
			}
			if (g_admin_pause_packets) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Audio is already paused.\n");
				return true;
			}
			
			g_admin_pause_packets = true;
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTTALK, "[Radio] Audio paused by " + plr.pev.netname + ".\n");
		}
		else if (args.ArgC() > 1 and (args[1] == "unpause" or args[1] == "resume")) {
			if (!isAdmin) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Admins only.\n");
				return true;
			}
			if (!g_admin_pause_packets) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Audio is already resumed.\n");
				return true;
			}
			
			g_admin_pause_packets = false;
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTTALK, "[Radio] Audio resumed by " + plr.pev.netname + ".\n");
		}
		else if (args.ArgC() > 1 and args[1] == "stop") {
			string arg = args[2];
			
			float delta = g_Engine.time - state.lastLaggyCmd;
			if (delta < 1 and delta >= 0) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Wait a second before using that command.\n");
				return true;
			}
			state.lastLaggyCmd = g_Engine.time;
			
			if (state.channel == -1) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] You must be in a radio channel to use this command.\n");
				return true;
			}
			
			Channel@ chan = @g_channels[state.channel];
			
			if (arg == "") {
				chan.stopMusic(plr, -1, false);
			} else if (arg == "first") {
				chan.stopMusic(plr, chan.activeSongs.size()-1, false);
			} else if (arg == "last") {
				chan.stopMusic(plr, 0, false);
			} else if (arg == "clear") {
				chan.stopMusic(plr, -1, true);
			} else if (arg == "speak") {
				send_voice_server_message("Radio\\en\\100\\.radio stop speak");
			} else if (arg == "global") {
				if (!isAdmin) {
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Admins only.\n");
					return true;
				}
				send_voice_server_message("Radio\\en\\100\\.radio stop global");
			}
			
			return true;
		}
		else if (args.ArgC() > 2 and args[1] == "name") {
			string newName = args[2];
			
			float delta = g_Engine.time - state.lastLaggyCmd;
			if (delta < 1 and delta >= 0) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Wait a second before using that command.\n");
				return true;
			}
			state.lastLaggyCmd = g_Engine.time;
			
			if (state.channel == -1) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] You must be in a radio channel to use this command.\n");
				return true;
			}
			
			Channel@ chan = @g_channels[state.channel];
			chan.rename(plr, newName);
			
			return true;
		}
		else if (args.ArgC() > 1 and args[1] == "reliable") {
			state.reliablePackets = !state.reliablePackets;
			
			if (args.ArgC() > 2) {
				state.reliablePackets = atoi(args[2]) != 0;
			}
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Reliable packets " + (state.reliablePackets ? "enabled" : "disabled") + ".\n");
		}
		else if (args.ArgC() > 1 and args[1] == "list") {
			float delta = g_Engine.time - state.lastLaggyCmd;
			if (delta < 1 and delta >= 0) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Wait a second before using that command.\n");
				return true;
			}
			state.lastLaggyCmd = g_Engine.time;
			
			for (uint i = 0; i < g_channels.size(); i++) {
				Channel@ chan = g_channels[i];
				array<CBasePlayer@> listeners = chan.getChannelListeners();
				
				string title = chan.name;
				CBasePlayer@ dj = chan.getDj();
				
				title += dj !is null ? "  (DJ: " + dj.pev.netname + ")" : "";
				
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n\n" + title + "\n------------------");
				for (uint k = 0; k < listeners.size(); k++) {
					uint pos = (k+1);
					string spos = pos;
					if (pos < 10) {
						spos = " " + spos;
					}
					
					PlayerState@ lstate = getPlayerState(listeners[k]);
					string mute = "";
					if (lstate.muteMode == MUTE_TTS) {
						mute += " (Mute: speech)";
					} else if (lstate.muteMode == MUTE_VIDEOS) {
						mute += " (Mute: videos)";
					}
					
					string tts = " (TTS: " + lstate.lang + " " + lstate.pitch + ")";
					
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n" + spos + ") " + listeners[k].pev.netname + tts + mute);
				}
				
				if (listeners.size() == 0) {
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n(empty)");
				}
			}
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n\n");
		}
		else if (args.ArgC() > 1 and args[1] == "help") {
			showConsoleHelp(plr, !inConsole);
		}
		else if (args.ArgC() > 1 and args[1] == "block") {
			state.blockInvites = true;
			state.requestsAllowed = false;
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Blocked radio invites/requests.\n");
		}
		else if (args.ArgC() > 1 and args[1] == "unblock") {
			state.blockInvites = false;
			state.requestsAllowed = true;
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Unblocked radio invites/requests.\n");
		}
		else if (args.ArgC() > 1 and args[1] == "lang") {
			string code = args[2].ToLowercase();
			
			if (g_langs.exists(code)) {
				state.lang = code;
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] TTS language set to " + string(g_langs[code]) + ".\n");
			} else {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Invalid language code \"" + code + "\". Type \".radio langs\" for a list of valid codes.\n");
			}
			
			return true; // hide from chat relay
		}
		else if (args.ArgC() > 1 and args[1] == "langs") {
			float delta = g_Engine.time - state.lastLaggyCmd;
			if (delta < 1 and delta >= 0) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Wait a second before using that command.\n");
				return true;
			}
			state.lastLaggyCmd = g_Engine.time;
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] TTS language codes sent to your console.\n");
			
			array<string>@ langKeys = g_langs.getKeys();
			array<string> lines;
			
			langKeys.sort(function(a,b) { return string(g_langs[a]) < string(g_langs[b]); });
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "Valid language codes:\n");
			for (uint i = 0; i < g_langs.size(); i++) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    " + langKeys[i] + " = " + string(g_langs[langKeys[i]]) + "\n");
			}
			
			return true; // hide from chat relay
		}
		else if (args.ArgC() > 1 and args[1] == "pitch") {
			int pitch = atoi(args[2]);
			
			if (pitch < 10) {
				pitch = 10;
			} else if (pitch > 200) {
				pitch = 200;
			}
			
			state.pitch = pitch;
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] TTS pitch set to " + pitch + ".\n");
			
			return true; // hide from chat relay
		}
		else if (args.ArgC() > 1 and args[1] == "debug") {
			state.isDebugging = !state.isDebugging;
			
			if (state.isDebugging) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Debug mode ON.\n");
			} else {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Debug mode OFF.\n");
			}
		}
		
		
		return true;
	} else if (lowerArg.Find("https://") <= 1 || lowerArg.Find("http://") <= 1) {	
		if (state.channel != -1) {
			lowerArg.Trim();
			bool isHiddenChat = lowerArg.Find("https://") == 1 || lowerArg.Find("http://") == 1;
			
			Channel@ chan = @g_channels[state.channel];
			bool canDj = chan.canDj(plr);
			
			string url = args[0];
			bool playNow = url[0] == '!';
			if (isHiddenChat)
				url = url.SubString(1);
			
			Song song;
			song.path = url;
			song.loadState = SONG_UNLOADED;
			song.id = g_song_id;
			song.requester = plr.pev.netname;
			song.args = args[1];
			
			g_song_id += 1;
			
			if (g_admin_pause_packets || g_lag_pause_packets) {
				int playerLimit = g_is_scripted_map ? g_maxPlayers2.GetInt() : g_maxPlayers.GetInt();
				
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] The plugin is temporarily disabled to prevent lag.\n");
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] It will re-enable when there are less than " + (playerLimit+1) + " players in the server.\n");
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] The player limit is especially low because this map uses scripted weapons, which can be laggy on their own.\n");
				return true;
			}
			
			if (playNow and int(chan.activeSongs.size()) >= chan.maxStreams) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] This channel can't play more than " + chan.maxStreams + " videos at the same time.\n");
				return true;
			}
			
			if (!canDj)  {
				if (int(chan.queue.size()) >= g_maxQueue.GetInt()) {
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Can't request now. The queue is full.\n");
				}
				else if (!state.shouldRequestCooldown(plr)) {
					if (chan.requestSong(plr, song)) {
						state.lastRequest = g_Engine.time;
					}
				}
			}
			else {
				if (playNow) {
					chan.playSong(song);
				} else {
					chan.queueSong(plr, song);
				}
			}
			
			return isHiddenChat;
		}
	} else if (args[0].Length() > 0) {
		if (g_any_radio_listeners and lowerArg.Find("https://") != 0 and lowerArg.Find("http://") != 0) {
			// speak the message
			send_voice_server_message("" + plr.pev.netname + "\\" + state.lang + "\\" + state.pitch + "\\" + args.GetCommandString());
		}
		if (args[0][0] == '~') {
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTCONSOLE, "[Radio][TTS] " + plr.pev.netname + ": " + args.GetCommandString() + "\n");
			return true;
		}
	}
	
	return false;
}

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}
