#include "../inc/RelaySay"
#include "Channel"
#include "menus"
#include "songloader"
#include "util"

// TODO:
// - search for songs
// - kick inactive DJs (no song for long time)
// - invite with text message instead of menu
// - show who else is listening/desynced with music sprites or smth
// - alt+tab can run twice or smth
// - pausefix <float> (only run once per sec)
// - let dj rename channel
// - invite cooldowns should use datetime

// Bugs that can't be fixed:
// prevent map music playing if radio is on:
//   - Can't stop ambient_music per player (user-only flag enabled after it spawns)
//   - Can't stop the music with StopSound or PlaySound on the MUSIC channel
//   - Custom entity can't play music at an offset for when someone joins late
//   - Enabling user-only flag and adding custom logic will break playing at an offset
//   - No way to know how often to send cl_stopsound without reading sound files to get duration

const string SONG_FILE_PATH = "scripts/plugins/Radio/songs.txt";
const string MUSIC_PACK_PATH = "scripts/plugins/Radio/music_packs.txt";

CCVar@ g_inviteCooldown;
CCVar@ g_requestCooldown;
CCVar@ g_djSwapCooldown;
CCVar@ g_skipSongCooldown;
CCVar@ g_djReserveTime;
CCVar@ g_listenerWaitTime;
CCVar@ g_maxQueue;
CCVar@ g_channelCount;

CClientCommand _radio("radio", "radio commands", @consoleCmd );

dictionary g_player_states;
array<Channel> g_channels;
array<Song> g_songs;
FileNode g_root_folder;

array<MusicPack> g_music_packs;
string g_music_pack_update_time;
string g_version_check_file;
string g_version_check_spr;
string g_root_path;

array<int> g_player_lag_status;

dictionary g_level_changers; // don't restart the music for these players on level changes

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
	int channel = -1;
	DateTime tuneTime; // last time player chose a channel (for displaying desync info)
	dictionary lastInviteTime; // for invite cooldowns per player and for \everyone
	float lastRequest; // for request cooldowns
	float lastDjToggle; // for cooldown
	float lastSongSkip; // for cooldown
	bool focusHackEnabled = false;
	bool showHud = true;
	bool neverUsedBefore = true;
	bool playAfterFullyLoaded = false; // should start music when this player fully loads
	bool sawUpdateNotification = false; // only show the UPDATE NOW sprite once per map
	
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
}

class Song {
	string title;
	string artist;
	string path;
	uint lengthMillis; // duration in milliseconds
	
	string getName() {
		return artist + " - " + title;
	}
	
	string getMp3PlayCommand() {
		string mp3 = path; // don't modify the original var
		return "mp3 play " + g_root_path + mp3.Replace(".mp3", "");
	}
}

class FileNode {
	string name;
	Song@ file = null;
	array<FileNode@> children;
}

class MusicPack {
	string link;
	string desc;
	
	string getSimpleDesc() {
		string simple = desc;
		return simple.Replace("\\r", "").Replace("\\w", "").Replace("\\d", "").Replace("\n", " ");
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
	@g_skipSongCooldown = CCVar("skipSongCooldown", 10, "DJ mode toggle cooldown", ConCommandFlag::AdminOnly);
	@g_djReserveTime = CCVar("djReserveTime", 240, "Time to reserve DJ slots after level change", ConCommandFlag::AdminOnly);
	@g_listenerWaitTime = CCVar("listenerWaitTime", 30, "Time to wait for listeners before starting new music after a map change", ConCommandFlag::AdminOnly);
	@g_maxQueue = CCVar("maxQueue", 8, "Max songs that can be queued", ConCommandFlag::AdminOnly);
	@g_channelCount = CCVar("channelCount", 3, "Number of available channels", ConCommandFlag::AdminOnly);
	
	g_channels.resize(g_channelCount.GetInt());
	
	for (uint i = 0; i < g_channels.size(); i++) {
		g_channels[i].name = "Channel " + (i+1);
		g_channels[i].id = i;
	}
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		g_level_changers[getPlayerUniqueId(plr)] = true;
	}
	
	g_root_folder.name = g_root_path;
	loadSongs();
	loadMusicPackInfo();
	
	g_Scheduler.SetInterval("radioThink", 0.5f, -1);
	g_Scheduler.SetInterval("radioResumeHack", 0.05f, -1);
	
	g_player_lag_status.resize(33);
}

void MapInit() {
	g_Game.PrecacheGeneric(g_root_path + g_version_check_file);
	
	g_Game.PrecacheGeneric("../" + g_root_path + g_version_check_spr);
	g_Game.PrecacheModel("../" + g_root_path + g_version_check_spr);
	
	loadSongs();
	loadMusicPackInfo();
	
	// Reset temporary vars
	array<string>@ states = g_player_states.getKeys();
	for (uint i = 0; i < states.length(); i++)
	{
		PlayerState@ state = cast< PlayerState@ >(g_player_states[states[i]]);
		state.lastInviteTime.clear();
		state.lastRequest = -9999;
		state.lastDjToggle = -9999;
		state.lastSongSkip = -9999;
		state.sawUpdateNotification = false;
	}
}

HookReturnCode MapChange() {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}

		PlayerState@ state = getPlayerState(plr);
		if (state.channel >= 0) {
			// This prevents music stopping during the map change.
			// Possibly not nice to do this. Someone might have customized the setting for some reason.
			clientCommand(plr, "mp3fadetime 999999");
		}
	}
	
	// wait before saving connected players in case classic mode is restarting the map
	if (g_Engine.time > 5) {
		for (uint i = 0; i < g_channels.size(); i++) {
			g_channels[i].rememberListeners();
		}
	}
	
	for (uint i = 0; i < 33; i++) {
		g_player_lag_status[i] = LAG_JOINING;
	}

	return HOOK_CONTINUE;
}

HookReturnCode ClientJoin(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	string id = getPlayerUniqueId(plr);
	
	if (!g_level_changers.exists(id)) {
		if (state.channel >= 0) {
			state.playAfterFullyLoaded = true;
		}
		
		g_level_changers[id] = true;
	}
	
	// always doing this in case someone left during a level change, preventing the value from resetting
	// TODO: actually can't do this because it cranks volume up if a fadeout is currently active
	//g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "[Radio] Your 'mp3fadetime' setting was reset to 2.\n");
	//clientCommand(plr, "mp3fadetime 2");
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientLeave(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	
	// TODO: this won't trigger for players who leave during level changes
	g_level_changers.delete(getPlayerUniqueId(plr));
	
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
		
		if (state.channel < 0) {
			continue;
		}
		
		Channel@ chan = g_channels[state.channel];
		
		if (state.playAfterFullyLoaded and g_player_lag_status[plr.entindex()] == LAG_NONE) {
			state.playAfterFullyLoaded = false;
			
			if (chan.queue.size() > 0) {
				Song@ song = chan.queue[0];
				clientCommand(plr, song.getMp3PlayCommand());
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Now playing: " + song.getName() + "\n");
				state.tuneTime = DateTime();
			}
		}

		if (state.showHud) {
			chan.updateHud(plr, state);
		}
	}
}

void radioResumeHack() {
	// spam the "cd resume" command to stop the music pausing when the game window loses focus
	// TODO: only do this when not pushing buttons
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		if (state.focusHackEnabled and state.channel >= 0) {
			Channel@ chan = g_channels[state.channel];
		
			clientCommand(plr, "cd resume", MSG_ONE_UNRELIABLE);
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
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '------------------------------ Radio Commands ------------------------------\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".radio" to open the radio menu.\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".radio faq" for answers to frequently asked questions.\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".radio hud" to toggle the radio HUD.\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".radio list" to show who\'s listening.\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".radio pausefix" to toggle the music-pause fix.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    This prevents the music pausing when the game window loses focus (alt+tab).\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    In order for this to work you need to also set "cl_filterstuffcmd 0" in the console.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    DANGER! DANGER! YOU DO THIS AT YOUR OWN RISK!\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    DISABLING FILTERSTUFF ALLOWS THE SERVER TO RUN ***ANY*** COMMAND IN YOUR CONSOLE!!1!!\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    In the past this has been abused for things like rebinding your jump button to crash the game.\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Only disable cl_filterstuffcmd on servers you trust. Add "cl_filterstuffcmd 1" to userconfig.cfg\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    so you don\'t have to remember to turn it back on.\n\n');
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\n--------------------------------------------------------------------------\n');

	if (showChatMessage) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, '[Radio] Help info sent to your console.\n');
	}
}

void showConsoleFaq(CBasePlayer@ plr, bool showChatMessage) {
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "------------------------------ Radio FAQ ------------------------------\n\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "Can't hear music?\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "  1) Download and install the latest music pack\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "  2) Pick \"Test installation\" in the Help menu to test your installation\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "  3) Check that your music volume isn't too low in Options -> Audio\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "  4) Pick \"Restart music\" in the Help menu and it should start working\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "  You will see 'Could not find music file' errors in the console if you didn't install properly.\n");
	
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\nSong changing too soon?\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "  Your music playback was desynced from the server. This happens when:\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    - You joined a channel after the music started\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    - You alt-tabbed out of the game (music pauses when the game isn't in focus)\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "  To fix the desync, just wait for the next song to start and keep the game window in focus.\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "  You might want to try the pausefix command if this happens a lot (see .radio help).\n");
	
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\nMusic pack download links (choose which quality you want):\n");
	string stringu = "";
	for (uint i = 0; i < g_music_packs.size(); i++) {		
		string desc = g_music_packs[i].getSimpleDesc();
		string link = g_music_packs[i].link;
		
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "  - " + desc + "\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    " + link + "\n\n");
	}
	
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "Music pack last updated:\n" + g_music_pack_update_time + "\n");
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n------------------------------------------------------------------------\n");

	if (showChatMessage) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] FAQ sent to your console.\n");
	}
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args, bool inConsole) {
	bool isAdmin = g_PlayerFuncs.AdminLevel(plr) >= ADMIN_YES;
	PlayerState@ state = getPlayerState(plr);
	
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
		else if (args.ArgC() > 1 and args[1] == "pausefix") {
			state.focusHackEnabled = !state.focusHackEnabled;
			
			if (args.ArgC() > 2) {
				state.focusHackEnabled = atoi(args[2]) != 0;
			}
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Music-pause fix " + (state.focusHackEnabled ? "enabled" : "disabled") + ".\n");
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
		else if (args.ArgC() > 1 and args[1] == "faq") {
			showConsoleFaq(plr, !inConsole);
		}
		
		return true;
	}
	
	return false;
}

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}
