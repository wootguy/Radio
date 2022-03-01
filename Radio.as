#include "../inc/RelaySay"
#include "Channel"
#include "menus"
#include "util"
//#include "target_cdaudio_radio"
#include "ambient_music_radio"
#include "FakeMic"

// BIG TODO:
// - tts?
// - play at an offset

// TODO:
// - kick inactive DJs (no song for long time)
// - invite with text message instead of menu
// - show who else is listening/desynced with music sprites or smth
// - alt+tab can run twice or smth
// - let dj rename channel
// - invite cooldowns should use datetime
// - read volume level from ambient_music when scripts are able to read it from the bsp
// - set voice ent to DJ or requester if server is full, instead of player 0
// - option to block requests from specific player

const string SONG_FILE_PATH = "scripts/plugins/Radio/songs.txt";
const string MUSIC_PACK_PATH = "scripts/plugins/Radio/music_packs.txt";
const int MAX_SERVER_ACTIVE_SONGS = 16;
const int SONG_REQUEST_TIMEOUT = 20;

CCVar@ g_inviteCooldown;
CCVar@ g_requestCooldown;
CCVar@ g_djSwapCooldown;
CCVar@ g_skipSongCooldown;
CCVar@ g_djReserveTime;
CCVar@ g_maxQueue;
CCVar@ g_channelCount;

CClientCommand _radio("radio", "radio commands", @consoleCmd );
CClientCommand _radio2("radiodbg", "radio commands", @consoleCmd );

dictionary g_player_states;
array<Channel> g_channels;

array<int> g_player_lag_status;
uint g_song_id = 1;

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



class PlayerState {
	int channel = 0;
	dictionary lastInviteTime; // for invite cooldowns per player and for \everyone
	float lastRequest; // for request cooldowns
	float lastDjToggle; // for cooldown
	float lastSongSkip; // for cooldown
	bool showHud = true;
	bool playAfterFullyLoaded = true; // toggle map music when fully loaded into the map
	bool neverUsedBefore = true;
	bool isDebugging = false;
	bool requestsAllowed = true;
	
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
	
	bool isRadioListener() {
		return channel >= 0;
	}
}

enum SONG_LOAD_STATES {
	SONG_UNLOADED,
	SONG_LOADING,
	SONG_LOADED,
	SONG_FAILED
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
	
	string getClippedName(int length) {
		string name = getName();
		
		if (int(name.Length()) > length) {
			int sz = (length-4) / 2;
			return name.SubString(0,sz) + " .. " + name.SubString(name.Length()-sz);
		}
		
		return name;
	}
	
	string getName() const {
		if (artist.Length() == 0) {
			return title.Length() > 0 ? title : path;
		}
		return artist + " - " + title;
	}
	
	int getTimeLeft() {
		if (loadState != SONG_LOADED) {
			startTime = DateTime();
		}
		int diff = int(TimeDifference(DateTime(), startTime).GetTimeDifference());
		int songLen = ((lengthMillis + 999) / 1000) - (offset/1000);
		return songLen - diff;
	}
	
	bool isFinished() {
		return loadState == SONG_FAILED or (loadState == SONG_LOADED and getTimeLeft() <= 0);
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
	
	@g_inviteCooldown = CCVar("inviteCooldown", 600, "Radio invite cooldown", ConCommandFlag::AdminOnly);
	@g_requestCooldown = CCVar("requestCooldown", 300, "Song request cooldown", ConCommandFlag::AdminOnly);
	@g_djSwapCooldown = CCVar("djSwapCooldown", 5, "DJ mode toggle cooldown", ConCommandFlag::AdminOnly);
	@g_skipSongCooldown = CCVar("skipSongCooldown", 10, "Audio stop cooldown", ConCommandFlag::AdminOnly);
	@g_djReserveTime = CCVar("djReserveTime", 240, "Time to reserve DJ slots after level change", ConCommandFlag::AdminOnly);
	@g_maxQueue = CCVar("maxQueue", 8, "Max songs that can be queued", ConCommandFlag::AdminOnly);
	@g_channelCount = CCVar("channelCount", 3, "Number of available channels", ConCommandFlag::AdminOnly);
	
	g_channels.resize(g_channelCount.GetInt());
	
	for (uint i = 0; i < g_channels.size(); i++) {
		g_channels[i].name = "Channel " + (i+1);
		g_channels[i].id = i;
		g_channels[i].maxStreams = 2;
		
		if (i == 0) {
			g_channels[i].spamMode = true;
			g_channels[i].maxStreams = 12;
		}
	}
	
	g_Scheduler.SetInterval("radioThink", 0.5f, -1);
	
	g_voice_ent_idx = getEmptyPlayerSlotIdx();
	load_samples();
	play_samples(false);
	
	g_player_lag_status.resize(33);
	
	send_voice_server_message("Radio\\en\\100\\.mstop");
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
	
	for (uint i = 0; i < g_channels.size(); i++) {
		g_channels[i].lastSongRequest = 0;
	}
}

int g_replaced_cdaudio = 0;
int g_replaced_music = 0;
void MapActivate() {
	//g_CustomEntityFuncs.RegisterCustomEntity( "target_cdaudio_radio", "target_cdaudio_radio" );
	//g_CustomEntityFuncs.RegisterCustomEntity( "AmbientMusicRadio::ambient_music_radio", "ambient_music_radio" );
	
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
	
	g_voice_ent_idx = getEmptyPlayerSlotIdx();
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientLeave(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	
	if (state.channel >= 0) {
		if (g_channels[state.channel].currentDj == getPlayerUniqueId(plr)) {
			g_channels[state.channel].currentDj = "";
		}
	}
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientSay( SayParameters@ pParams ) {
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	
	if (doCommand(plr, args, false)) {
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
			AmbientMusicRadio::toggleMapMusic(plr, !state.isRadioListener());
		}

		if (state.isRadioListener() and state.showHud) {
			g_channels[state.channel].updateHud(plr, state);
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

void showConsoleHelp(CBasePlayer@ plr, bool showChatMessage) {
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '------------------------------ Radio Help ------------------------------\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".radio" to open the radio menu.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".radio list" to show who\'s listening.\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'To queue a video, paste a youtube link in the chat. Use the "say" command in console to do this. Example:\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    say https://www.youtube.com/watch?v=b8HO6hba9ZE\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'To bypass the queue, add a "!" before your link. Example:\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    say !https://www.youtube.com/watch?v=b8HO6hba9ZEn\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Can\'t hear anything?\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Check that you haven\'t disabled voice. "voice_enable" should be set to 1.\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Audio is stuttering?\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Try typing "stopsound" in console. Voice playback often breaks after viewing a map cutscene.\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Audio is too loud/quiet?\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    You can adjust voice volume with "voice_scale" in console. Type stopsound to apply your change.\n');
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
				openMenuChannelSelect(EHandle(plr));
			}
		}
		else if (args.ArgC() > 1 and args[1] == "hud") {
			state.showHud = !state.showHud;
			
			if (args.ArgC() > 2) {
				state.showHud = atoi(args[2]) != 0;
			}
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] HUD " + (state.showHud ? "enabled" : "disabled") + ".\n");
		}
		else if (args.ArgC() > 1 and args[1] == "list") {
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
					
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n" + spos + ") " + listeners[k].pev.netname);
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
		else if (args.ArgC() > 1 and args[1] == "debug") {		
			state.isDebugging = !state.isDebugging;
			
			if (state.isDebugging) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Debug mode ON.\n");
			} else {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Debug mode OFF.\n");
			}
		}
		
		return true;
	} else if (lowerArg.Find("https://www.youtube.com") <= 1 || lowerArg.Find("https://youtu.be") <= 1) {
		if (state.channel != -1) {
			Channel@ chan = @g_channels[state.channel];
			bool canDj = chan.canDj(plr);
			
			string url = args[0];
			bool playNow = url[0] == '!';
			if (playNow) {
				url = url.SubString(1);
			}
			
			Song song;
			song.path = url;
			song.loadState = SONG_UNLOADED;
			song.id = g_song_id;
			song.requester = plr.pev.netname;
			
			g_song_id += 1;
			
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
					if (int(chan.activeSongs.size()) >= chan.maxStreams) {
						g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] This channel can't play more than " + chan.maxStreams + " videos at the same time.\n");
					} else {
						chan.playSong(song);
					}
				} else {
					chan.queueSong(plr, song);
				}
			}
			
			return true;
		}
	}
	
	return false;
}

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}
