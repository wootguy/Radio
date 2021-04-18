#include "../inc/RelaySay"
#include "Channel"
#include "songloader"
#include "util"

// TODO minor:
// - search for songs
// - kick inactive DJs (no song for long time)
// - invite with text message instead of menu
// - prevent map music playing if radio is on
// - show who else is listening/desynced with music sprites or smth
// - alt+tab can run twice or smth
// - pausefix <float> (only run once per sec)
// - let dj rename channel
// - invite cooldowns should use datetime

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

dictionary g_player_states;
array<Channel> g_channels;
array<Song> g_songs;
FileNode g_root_folder;

array<MusicPack> g_music_packs;
string g_music_pack_update_time;
string g_version_check_file;
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
		if (delta < g_skipSongCooldown.GetInt()) {			
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
	g_Game.PrecacheGeneric(g_root_path + "classical/richard_wagner_ride_of_the_valkyries.mp3"); // forgot to add this to the music packs
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
			state.playAfterFullyLoaded = false;
			
			if (state.channel >= 0 and g_channels[state.channel].queue.size() > 0) {
				Song@ song = g_channels[state.channel].queue[0];
				clientCommand(plr, song.getMp3PlayCommand());
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Now playing: " + song.getName() + "\n");
				state.tuneTime = DateTime();
			}
		}

		if (state.showHud and state.channel >= 0) {
			g_channels[state.channel].updateHud(plr, state);
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


void callbackMenuRadio(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	string option = "";
	item.m_pUserData.retrieve(option);
	
	bool canDj = true;
	Channel@ chan = null;
	if (state.channel >= 0) {
		canDj = g_channels[state.channel].canDj(plr);
		@chan = @g_channels[state.channel];
	}
	
	if (option == "channels") {
		g_Scheduler.SetTimeout("openMenuChannelSelect", 0.0f, EHandle(plr));
	}
	else if (option == "turn-off") {
		if (state.channel >= 0) {
			chan.handlePlayerLeave(plr);
		}
		
		state.channel = -1;
		
		string msg = "[Radio] Turned off.";
		if (state.neverUsedBefore) {
			state.neverUsedBefore = false;
			msg += " Say .radio to turn it back on.";
		}
		
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, msg + "\n");
		clientCommand(plr, "mp3 stop");
		
		HUDTextParams params;
		params.holdTime = 0.5f;
		params.x = -1;
		params.y = 0.0001;
		params.channel = 2;
		
		g_PlayerFuncs.HudMessage(plr, params, "");
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "add-song") {
		g_Scheduler.SetTimeout("openMenuSong", 0.0f, EHandle(plr), "", 0);
	}
	else if (option == "skip-song") {
		if (!canDj) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Only the DJ can skip songs.\n");
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		if (state.shouldSongSkipCooldown(plr)) {
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		if (chan.queue.size() == 0) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] No song is playing.\n");
		}
		else {
			chan.shouldSkipSong = plr.pev.netname;
			state.lastSongSkip = g_Engine.time;
		}
		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "edit-queue") {
		if (chan.queue.size() <= 1) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] The queue is empty.\n");
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), 0);
	}
	else if (option == "become-dj") {
		CBasePlayer@ currentDj = chan.getDj();
		
		if (chan.isDjReserved()) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] DJ slot is reserved by someone who hasn't finished joining yet.\n");
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		if (state.shouldDjToggleCooldown(plr)) {
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		if (currentDj !is null) {
			if (currentDj.entindex() != plr.entindex()) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] " + currentDj.pev.netname + " must stop DJ'ing first.\n");
			} else {
				chan.announce("" + currentDj.pev.netname + " is not the DJ anymore.\n");
				chan.currentDj = "";
			}
		}
		else {
			chan.currentDj = getPlayerUniqueId(plr);
			chan.announce("" + plr.pev.netname + " is now the DJ!");
		}
		state.lastDjToggle = g_Engine.time;
		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "invite") {		
		g_Scheduler.SetTimeout("openMenuInvite", 0.0f, EHandle(plr));
	}
	else if (option == "help") {
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	} else {
		if (state.neverUsedBefore) {
			state.neverUsedBefore = false;
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Say .radio if you want to re-open the menu.\n");
		}
	}
}

void callbackMenuChannelSelect(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	string option = "";
	item.m_pUserData.retrieve(option);
	
	string chanPrefix = "channel-";

	if (option.Find(chanPrefix) == 0) {
		int oldChannel = state.channel;
		state.channel = atoi(option.SubString(chanPrefix.Length()));
		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
		
		if (oldChannel == state.channel) {
			return;
		}
		
		if (oldChannel >= 0) {
			g_channels[oldChannel].handlePlayerLeave(plr);
		}
		
		if (g_channels[state.channel].queue.size() > 0) {
			clientCommand(plr, g_channels[state.channel].queue[0].getMp3PlayCommand());
		} else {
			clientCommand(plr, "mp3 stop");
		}
		
		g_channels[state.channel].announce("" + plr.pev.netname + " tuned in.", HUD_PRINTNOTIFY, plr);
		state.tuneTime = DateTime();
	}
}

void callbackMenuSong(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];
	bool canDj = chan.canDj(plr);

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option.Find("search:") == 0) {
		string path = option.Length() > 7 ? option.SubString(7) : "";
		g_Scheduler.SetTimeout("openMenuSong", 0.0f, EHandle(plr), path, 0);
	}
	else if (option.Find("play:") == 0) {
		array<string> parts = option.Split(":");
		int page = atoi(parts[1]);
		string path = parts[2];
		string parentPath = getParentFolder(path);
		
		Song@ song = getNodeFromPath(path).file;
		
		if (!canDj)  {
			if (!state.shouldRequestCooldown(plr)) {
				state.lastRequest = g_Engine.time;
				string helpPath = parentPath;
				if (helpPath.Length() > 0) {
					helpPath += "/";
				}
				chan.announce("" + plr.pev.netname + " requested: " + helpPath + song.getName());
			}
		}
		else {			
			chan.queueSong(plr, song);
		}
		
		g_Scheduler.SetTimeout("openMenuSong", 0.0f, EHandle(plr), parentPath, page);
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
}

void callbackMenuEditQueue(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];
	bool canDj = chan.canDj(plr);

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option.Find("edit-slot-") == 0) {
		int slot = atoi(option.SubString(10));
		
		if (!canDj) {
			slot = 0;
		}
		
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), slot);
	}
	else if (option.Find("move-up-") == 0) {
		int slot = atoi(option.SubString(8));
		int newSlot = slot;
		
		if (slot > 1) {
			chan.announce("" + plr.pev.netname + " moved up: " + chan.queue[slot].getName(), HUD_PRINTNOTIFY);
			Song@ temp = chan.queue[slot];
			@chan.queue[slot] = @chan.queue[slot-1];
			@chan.queue[slot-1] = @temp;
			newSlot = slot-1;
		}
		
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), newSlot);
	}
	else if (option.Find("move-down-") == 0) {
		int slot = atoi(option.SubString(10));
		int newSlot = slot;
		
		if (slot < int(chan.queue.size())-1) {
			chan.announce("" + plr.pev.netname + " moved down: " + chan.queue[slot].getName(), HUD_PRINTNOTIFY);
			Song@ temp = chan.queue[slot];
			@chan.queue[slot] = @chan.queue[slot+1];
			@chan.queue[slot+1] = @temp;
			newSlot = slot+1;
		}
		
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), newSlot);
	}
	else if (option.Find("remove-") == 0) {
		int slot = atoi(option.SubString(7));
		
		if (slot < int(chan.queue.size())) {
			HUD msgType = chan.hasDj() ? HUD_PRINTNOTIFY : HUD_PRINTTALK;
			chan.announce("" + plr.pev.netname + " removed: " + chan.queue[slot].getName(), msgType);
			chan.queue.removeAt(slot);
		}
		
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), 0);
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "edit-queue") {
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), 0);
	}
}

void callbackMenuInvite(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option == "inviteall") {
		int inviteCount = 0;
	
		if (state.shouldInviteCooldown(plr, "\\everyone")) {
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
	
		for ( int i = 1; i <= g_Engine.maxClients; i++ )
		{
			CBasePlayer@ target = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (target is null or !target.IsConnected() or plr.entindex() == target.entindex()) {
				continue;
			}
			PlayerState@ targetState = getPlayerState(target);
			
			if (targetState.channel == state.channel) {
				continue;
			}
			
			g_Scheduler.SetTimeout("openMenuInviteRequest", 0.5f, EHandle(target), "" + plr.pev.netname, state.channel);
			inviteCount++;
		}
		
		if (inviteCount == 0) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] No one to invite.\n");
		}
		else {
			state.lastInviteTime["\\everyone"] = g_Engine.time;
			chan.announce("" + plr.pev.netname + " invited " + inviteCount + " players");
		}

		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option.Find("invite-") == 0) {
		string targetId = option.SubString(7);
		CBasePlayer@ target = getPlayerByUniqueId(targetId);
		
		if (state.shouldInviteCooldown(plr, targetId)) {
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		if (target !is null) {
			PlayerState@ targetState = getPlayerState(target);
			g_Scheduler.SetTimeout("openMenuInviteRequest", 0.5f, EHandle(target), "" + plr.pev.netname, state.channel);
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Invitation sent to " + target.pev.netname + "\n");
			
			state.lastInviteTime[targetId] = g_Engine.time;
		} else {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Invitation failed. Player left the game.\n");
		}
		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option.Find("invite-decline-") == 0) {
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
}

void callbackMenuHelp(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option == "restart-music") {
		if (chan.queue.size() > 0) {
			Song@ song = chan.queue[0];
			clientCommand(plr, song.getMp3PlayCommand());
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Now playing: " + song.getName() + "\n");
			state.tuneTime = DateTime();
		} else {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] There is no music playing on " + chan.name + "\n");
		}
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "download-pack") {
		g_Scheduler.SetTimeout("openMenuDownload", 0.0f, EHandle(plr));
	}
	else if (option == "help-commands") {
		showConsoleHelp(plr, true);
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "test-install") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] You should be hearing a text-to-speech voice now. If not, increase music volume in Options -> Audio.\n");
		
		Song testSong = Song();
		testSong.path = g_version_check_file;
		
		clientCommand(plr, testSong.getMp3PlayCommand());
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
}

void callbackMenuDownload(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option.Find("download-") == 0) {
		int slot = atoi(option.SubString(9));
		
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Download link is below. You can copy it from the console. Extract to svencoop_downloads/\n\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, g_music_packs[slot].link + "\n\n");
		
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "help") {		
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
}



void openMenuRadio(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);	
	Channel@ chan = g_channels[state.channel];
	
	@g_menus[eidx] = CTextMenu(@callbackMenuRadio);
	g_menus[eidx].SetTitle("\\yRadio - " + chan.name);

	CBasePlayer@ dj = chan.getDj();
	bool isDjReserved = chan.isDjReserved();
	bool canDj = chan.canDj(plr);
	bool isDj = dj !is null and dj.entindex() == plr.entindex();

	g_menus[eidx].AddItem("\\wHelp\\y", any("help"));
	g_menus[eidx].AddItem("\\wTurn off\\y", any("turn-off"));
	g_menus[eidx].AddItem("\\wChange channel\\y", any("channels"));
	g_menus[eidx].AddItem("\\w" + (canDj ? "Queue" : "Request") + " song" + "\\y", any("add-song"));
	g_menus[eidx].AddItem("\\w" + (canDj ? "Edit" : "View") + " queue  " + chan.getQueueCountString() + "\\y", any("edit-queue"));
	g_menus[eidx].AddItem("\\wSkip song\\y", any("skip-song"));
	g_menus[eidx].AddItem("\\w" + (isDj ? "Quit DJ" : "Become DJ") + "\\y", any("become-dj"));
	g_menus[eidx].AddItem("\\wInvite\\y", any("invite"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuChannelSelect(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	
	@g_menus[eidx] = CTextMenu(@callbackMenuChannelSelect);
	g_menus[eidx].SetTitle("\\yRadio Channels\n");
	
	for (uint i = 0; i < g_channels.size(); i++) {
		Channel@ chan = g_channels[i];
		string label = "\\w" + chan.name;
		
		array<CBasePlayer@> listeners = chan.getChannelListeners();
		
		CBasePlayer@ dj = chan.getDj();
		
		if (listeners.size() > 0) {			
			label += "\\d  (" + listeners.size() + " listening)";
		}
		
		Song@ song = chan.queue.size() > 0 ? chan.queue[0] : null;
		label += "\n\\y      Current DJ:\\w " + (dj !is null ? string(dj.pev.netname) : "\\d(none)");
		label += "\n\\y      Now Playing:\\w " + (song !is null ? song.getName() : "\\d(nothing)");
		
		label += "\n\\y";
		
		g_menus[eidx].AddItem(label, any("channel-" + i));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuEditQueue(EHandle h_plr, int selectedSlot) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[state.channel];
	
	string title = chan.canDj(plr) ? "Edit queue" : "View queue";
	
	@g_menus[eidx] = CTextMenu(@callbackMenuEditQueue);
	
	if (selectedSlot == 0) {
		g_menus[eidx].SetTitle("\\y" + chan.name + " - " + title);
		g_menus[eidx].AddItem("\\w..\\y", any("main-menu"));
		
		for (uint i = 1; i < chan.queue.size(); i++) {
			string label = "\\w" + chan.queue[i].getName() + "\\y";
			
			// try to keep the menu spacing the same in both edit modes
			if (i == chan.queue.size()-1) {
				if (chan.queue.size() <= 3) {
					label += "\n\n\n\n";
				}
				else {
					label += "\n\n\n\n";
					
					if (chan.queue.size() > 1) {
						label += "\n\n\n";
					}
					if (chan.queue.size() > 5) {
						label += "\n\n";
					}
				}
			}
			
			g_menus[eidx].AddItem(label, any("edit-slot-" + i));
		}
	} else {
		string label = "\\y" + chan.name + " - " + title + "\n";
		
		for (uint i = 1; i < chan.queue.size(); i++) {
			string color = int(i) == selectedSlot ? "\\r" : "\\w";
			label += "\n" + color + "    " + chan.queue[i].getName() + "\\y";
		}
		
		label += "\n\n\\yAction:";
		
		g_menus[eidx].SetTitle(label);
		g_menus[eidx].AddItem("\\wCancel\\y", any("edit-queue"));
		g_menus[eidx].AddItem("\\wMove up\\y", any("move-up-" + selectedSlot));
		g_menus[eidx].AddItem("\\wMove down\\y", any("move-down-" + selectedSlot));
		g_menus[eidx].AddItem("\\wRemove\\y", any("remove-" + selectedSlot));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuSong(EHandle h_plr, string path, int page) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[state.channel];
	
	string prefix = "";
	if (path.Length() > 0) {
		prefix = path + "/";
	}
	
	string title = "Queue Song  " + chan.getQueueCountString();
	if (!chan.canDj(plr)) {
		title = "Request Song";
	}
	
	@g_menus[eidx] = CTextMenu(@callbackMenuSong);
	g_menus[eidx].SetTitle("\\y" + chan.name + " - " + title + "\\y\n/" + prefix + "    ");	
	
	FileNode@ node = getNodeFromPath(path);
	
	string upCommand = "main-menu";
	
	if (path != "") {
		string upDir = getParentFolder(path);
		upCommand = "search:" + upDir;
	}
	
	g_menus[eidx].AddItem("\\w..\\y", any(upCommand));
	
	bool moreThanOnePage = (node.children.size()+1) > 9;
	
	for (uint i = 0; i < node.children.size(); i++) {
		FileNode@ child = node.children[i];
		
		if (moreThanOnePage and i != 0 && i % 6 == 0) {
			g_menus[eidx].AddItem("\\w..\\y", any(upCommand));
		}
		
		if (child.file !is null) {
			Song@ song = @child.file;
			string label = song.artist + " - " + song.title;
			
			bool isInQueue = false;
			bool nowPlaying = false;
			for (uint k = 0; k < chan.queue.size(); k++) {
				if (chan.queue[k].path == song.path) {
					nowPlaying = k == 0;
					isInQueue = k != 0;
					break;
				}
			}
			
			if (nowPlaying || isInQueue) {
				label = "\\r" + label;
			} else {
				label = "\\w" + label;
			}
			
			if (nowPlaying) {
				label += " \\d(now playing)";
			} else if (isInQueue) {
				label += " \\d(in queue)";
			}
			
			int itemPage = moreThanOnePage ? (i / 6) : 0;
			g_menus[eidx].AddItem(label + "\\y", any("play:" + itemPage + ":" + song.path));
		} else {
			g_menus[eidx].AddItem("\\w" + child.name + "/\\y", any("search:" + prefix + child.name));
		}
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, page, plr);
}

void openMenuInviteRequest(EHandle h_plr, string asker, int channel) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[channel];
	
	@g_menus[eidx] = CTextMenu(@callbackMenuChannelSelect);
	g_menus[eidx].SetTitle("\\yYou're invited to listen to\nthe radio on " + g_channels[channel].name + "\n-" + asker + "\n");
	
	g_menus[eidx].AddItem("\\wAccept\\y", any("channel-" + channel));
	
	string label = "\\wDecline\\y";
	label += "\n\nCurrent song:\n";
	
	Song@ song = chan.getSong();
	label += song !is null ? "\\w" + song.getName() : "\\d(nothing)";
	
	g_menus[eidx].AddItem(label + "\\y", any("exit"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuInvite(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[state.channel];
	
	@g_menus[eidx] = CTextMenu(@callbackMenuInvite);
	g_menus[eidx].SetTitle("\\y" + chan.name + " - Invite");
	
	g_menus[eidx].AddItem("\\w..\\y", any("main-menu"));
	g_menus[eidx].AddItem("\\rEveryone\\y", any("inviteall"));
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ target = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (target is null or !target.IsConnected() or plr.entindex() == target.entindex()) {
			continue;
		}
		
		PlayerState@ targetState = getPlayerState(target);
		if (targetState.channel == state.channel) {
			continue;
		}
		
		g_menus[eidx].AddItem("\\w" + target.pev.netname + "\\y", any("invite-" + getPlayerUniqueId(target)));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuHelp(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	
	@g_menus[eidx] = CTextMenu(@callbackMenuHelp);
	g_menus[eidx].SetTitle("\\yRadio Help");
	
	g_menus[eidx].AddItem("\\w..\\y", any("main-menu"));
	g_menus[eidx].AddItem("\\rDownload music pack\\y", any("download-pack"));
	g_menus[eidx].AddItem("\\wTest installation\\y", any("test-install"));
	g_menus[eidx].AddItem("\\wRestart music\\y", any("restart-music"));
	//g_menus[eidx].AddItem("\\wShow command help\\y", any("help-commands"));
	
	string label = "\\wShow command help\\y";
	label += "\n\nMusic pack last updated:\n\\r" + g_music_pack_update_time + "\\y";
	
	g_menus[eidx].AddItem(label, any("help-commands"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuDownload(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	
	@g_menus[eidx] = CTextMenu(@callbackMenuDownload);
	g_menus[eidx].SetTitle("\\yChoose Music Quality");
	g_menus[eidx].AddItem("\\w..\\y", any("help"));
	
	for (uint i = 0; i < g_music_packs.size(); i++) {		
		g_menus[eidx].AddItem("\\w" + g_music_packs[i].desc + "\\y", any("download-" + i));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
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

HookReturnCode ClientSay( SayParameters@ pParams ) {
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	
	if (doCommand(plr, args, false)) {
		pParams.ShouldHide = true;
	}
	
	return HOOK_CONTINUE;
}

CClientCommand _radio("radio", "radio commands", @consoleCmd );

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}