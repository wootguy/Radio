#include "../inc/RelaySay"
#include "Channel"
#include "songloader"
#include "util"

// TODO:
// - hide menu if vote menu opens
// - more console commands
// - search for songs
// - kick inactive DJs (no song for long time)
// - cant exit channel menu
// - messages are too spammy ("is now the dj spam")
// - invite with text message instead of menu
// - show new joiners how to reopen the menu if invited
// - prevent map music playing if radio is on
// - help console commands

const string SONG_FILE_PATH = "scripts/plugins/Radio/songs.txt";

CCVar@ g_rootPath;
CCVar@ g_musicPackUpdateTime;
CCVar@ g_musicPackVersionCheckFile;
CCVar@ g_musicPackLink;

CCVar@ g_inviteCooldown;
CCVar@ g_requestCooldown;
CCVar@ g_djSwapCooldown;
CCVar@ g_skipSongCooldown;
CCVar@ g_djReserveTime;
CCVar@ g_maxQueue;
CCVar@ g_channelCount;

dictionary g_player_states;
array<Channel> g_channels;
array<Song> g_songs;
FileNode g_root_folder;

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
	string keepMenuOpen = ""; // value is the menu type to open
	DateTime tuneTime; // last time player chose a channel (for displaying desync info)
	dictionary lastInviteTime; // for invite cooldowns per player and for \everyone
	float lastRequest; // for request cooldowns
	float lastDjToggle; // for cooldown
	float lastSongSkip; // for cooldown
	bool focusHackEnabled = true;
	bool showHud = false;
	
	bool shouldInviteCooldown(CBasePlayer@ plr, string id) {
		float inviteTime = -9999;
		if (lastInviteTime.exists(id)) {
			lastInviteTime.get(id, inviteTime);
		}
	
		float delta = g_Engine.time - inviteTime;
		if (delta < g_inviteCooldown.GetInt()) {
			if (int(id.Find("\\")) != -1) {
				id = id.Replace("\\", "");
			} else {
				CBasePlayer@ target = getPlayerByUniqueId(id);
				if (target !is null) {
					id = target.pev.netname;
				}
			}
			
			int waitTime = int((g_inviteCooldown.GetInt() - delta) + 0.99f);
			g_PlayerFuncs.SayText(plr, "[Radio] Wait " + waitTime + " seconds before inviting " + id + " again.\n");
			return true;
		}
		
		return false;
	}
	
	bool shouldRequestCooldown(CBasePlayer@ plr) {	
		float delta = g_Engine.time - lastRequest;
		if (delta < g_requestCooldown.GetInt()) {			
			int waitTime = int((g_inviteCooldown.GetInt() - delta) + 0.99f);
			g_PlayerFuncs.SayText(plr, "[Radio] Wait " + waitTime + " seconds before requesting another song.\n");
			return true;
		}
		
		return false;
	}
	
	bool shouldDjToggleCooldown(CBasePlayer@ plr) {	
		float delta = g_Engine.time - lastDjToggle;
		if (delta < g_djSwapCooldown.GetInt()) {			
			int waitTime = int((g_djSwapCooldown.GetInt() - delta) + 0.99f);
			g_PlayerFuncs.SayText(plr, "[Radio] Wait " + waitTime + " seconds before toggling DJ mode again.\n");
			return true;
		}
		
		return false;
	}
	
	bool shouldSongSkipCooldown(CBasePlayer@ plr) {	
		float delta = g_Engine.time - lastSongSkip;
		if (delta < g_skipSongCooldown.GetInt()) {			
			int waitTime = int((g_skipSongCooldown.GetInt() - delta) + 0.99f);
			g_PlayerFuncs.SayText(plr, "[Radio] Wait " + waitTime + " seconds before skipping another song.\n");
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
		return "mp3 play " + g_rootPath.GetString() + mp3.Replace(".mp3", "");
	}
}

class FileNode {
	string name;
	Song@ file = null;
	array<FileNode@> children;
}



void PluginInit() {
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @ClientJoin);
	g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @ClientLeave);
	g_Hooks.RegisterHook(Hooks::Player::ClientSay, @ClientSay);
	g_Hooks.RegisterHook(Hooks::Game::MapChange, @MapChange);
	
	@g_rootPath = CCVar("rootPath", "mp3/radio/", "radio music root folder", ConCommandFlag::AdminOnly);
	@g_musicPackUpdateTime = CCVar("musicPackUpdateTime", "????-??-??", "music pack last updated time", ConCommandFlag::AdminOnly);
	@g_musicPackVersionCheckFile = CCVar("musicPackVersionCheckFile", "version_check/v1.mp3", "version check file (used in help menu)", ConCommandFlag::AdminOnly);
	@g_musicPackLink = CCVar("musicPackLink", "https://asdf.com/qwerty.zip", "music pack download link", ConCommandFlag::AdminOnly);
	
	@g_inviteCooldown = CCVar("inviteCooldown", 240, "Radio invite cooldown", ConCommandFlag::AdminOnly);
	@g_requestCooldown = CCVar("requestCooldown", 240, "Song request cooldown", ConCommandFlag::AdminOnly);
	@g_djSwapCooldown = CCVar("g_djSwapCooldown", 5, "DJ mode toggle cooldown", ConCommandFlag::AdminOnly);
	@g_skipSongCooldown = CCVar("g_skipSongCooldown", 10, "DJ mode toggle cooldown", ConCommandFlag::AdminOnly);
	@g_djReserveTime = CCVar("djReserveTime", 240, "Time to reserve DJ slots after level change", ConCommandFlag::AdminOnly);
	@g_maxQueue = CCVar("maxQueue", 8, "Max songs that can be queued", ConCommandFlag::AdminOnly);
	@g_channelCount = CCVar("channelCount", 4, "Number of available channels", ConCommandFlag::AdminOnly);
	
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
	
	g_root_folder.name = g_rootPath.GetString();
	loadSongs();
	
	g_Scheduler.SetInterval("radioThink", 0.5f, -1);
	g_Scheduler.SetInterval("radioResumeHack", 0.05f, -1);
}

void MapInit() {
	g_Game.PrecacheGeneric(g_rootPath.GetString() + g_musicPackVersionCheckFile.GetString());
	loadSongs();
	
	// Reset temporary vars
	array<string>@ states = g_player_states.getKeys();
	for (uint i = 0; i < states.length(); i++)
	{
		PlayerState@ state = cast< PlayerState@ >(g_player_states[states[i]]);
		state.lastInviteTime.clear();
		state.lastRequest = -9999;
		state.lastDjToggle = -9999;
		state.lastSongSkip = -9999;
		state.keepMenuOpen = ""; // prevent overflows while parsing game info
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

	return HOOK_CONTINUE;
}

HookReturnCode ClientJoin(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	string id = getPlayerUniqueId(plr);
	
	if (!g_level_changers.exists(id)) {
		if (state.channel >= 0) {
			if (g_channels[state.channel].queue.size() > 0) {
				Song@ song = g_channels[state.channel].queue[0];
				clientCommand(plr, song.getMp3PlayCommand());
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Now playing: " + song.getName() + "\n");
				state.tuneTime = DateTime();
			}
		}
		
		g_level_changers[id] = true;
	}
	
	// always doing this in case someone left during a level change, preventing the value from resetting
	g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "[Radio] Your 'mp3fadetime' setting was reset to 2.\n");
	clientCommand(plr, "mp3fadetime 2");
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientLeave(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	
	// TODO: this won't trigger for players who leave during level changes
	g_level_changers.delete(getPlayerUniqueId(plr));
	state.keepMenuOpen = "";
	
	if (state.channel >= 0) {
		if (g_channels[state.channel].currentDj == getPlayerUniqueId(plr)) {
			g_channels[state.channel].currentDj = "";
		}
	}
	
	return HOOK_CONTINUE;
}

void radioThink() {	
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
		
		if (state.keepMenuOpen.Length() > 0) {
			g_Scheduler.SetTimeout(state.keepMenuOpen, 0.0f, EHandle(plr));
		}

		if (state.showHud and state.channel >= 0) {
			Channel@ chan = g_channels[state.channel];
			
			HUDTextParams params;
			params.effect = 0;
			params.fadeinTime = 0;
			params.fadeoutTime = 0.5f;
			params.holdTime = 1.0f;
			params.r1 = 255;
			params.g1 = 255;
			params.b1 = 255;
			
			params.x = -1;
			params.y = 0.0001;
			params.channel = 2;

			Song@ song = chan.getSong();
			CBasePlayer@ dj = chan.getDj();
			string djName = dj !is null ? " - " + dj.pev.netname : "";
			string msg = chan.name + djName + " - " + chan.getChannelListeners().size() + " listening";
			string songStr = (song !is null) ? song.getName() + "  " + formatTime(chan.getTimeLeft()) : "";
			
			g_PlayerFuncs.HudMessage(plr, params, msg + "\n" + songStr);
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
		
			clientCommand(plr, "cd resume");
		}
	}
}



void callbackMenuRadio(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);
	
	state.keepMenuOpen = "";

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
		
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Turned off.\n");
		clientCommand(plr, "mp3 stop");
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
			chan.shouldSkipSong = true;
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
	}
}

void callbackMenuChannelSelect(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);
	
	state.keepMenuOpen = "";

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
	
	state.keepMenuOpen = "";

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
	
	state.keepMenuOpen = "";

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
	
	state.keepMenuOpen = "";

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
			
			g_Scheduler.SetTimeout("openMenuInviteRequest", 0.5f, EHandle(target), "" + plr.pev.netname, state.channel, targetState.keepMenuOpen);
			targetState.keepMenuOpen = "";
			inviteCount++;
		}
		
		if (inviteCount == 0) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] No one to invite.\n");
		}
		else {
			state.lastInviteTime["\\everyone"] = g_Engine.time;
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Invitations sent to " + inviteCount + " players.\n");
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
			g_Scheduler.SetTimeout("openMenuInviteRequest", 0.5f, EHandle(target), "" + plr.pev.netname, state.channel, targetState.keepMenuOpen);
			targetState.keepMenuOpen = "";
			
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
	
	state.keepMenuOpen = "";

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
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Download link is below. You can copy it from the console.\n\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, g_musicPackLink.GetString() + "\n\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Extract to Steam/Common/Sven Co-op/svencoop_downloads/\n");
		
		
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "help-cant-hear") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Can't hear music?\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "  1) Download and install the latest music pack\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "  2) Pick \"Test installation\" to test your installation\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "  3) Check that your music volume isn't too low in Options -> Audio\n");
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "help-desync") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Song changing too soon?\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "  Your music playback was desynced from the server. There are a few causes for this:\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "    - You joined a channel after the music started (you'll see red desync text in this case)\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "    - You alt-tabbed out of the game (music pauses when the game isn't in focus)\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "    - Your game or PC was frozen for a few seconds\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "  To fix the desync, just wait for the next song to start and keep the game window in focus.\n");
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "help-commands") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Command help was sent to your console.\n");
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "test-install") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] You should be hearing a text-to-speech voice now. If not, increase your music volume in Options -> Audio\n");
		
		Song testSong = Song();
		testSong.path = g_musicPackVersionCheckFile.GetString();
		
		clientCommand(plr, testSong.getMp3PlayCommand());
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
}



void openMenuRadio(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[state.channel]; // TODO: invalid index somehow
	
	state.keepMenuOpen = "openMenuRadio";
	
	string title = "\\y" + chan.name;
	title += "  \\d(" + chan.getChannelListeners().size() + " listening)\\y";
	
	@g_menus[eidx] = CTextMenu(@callbackMenuRadio);
	g_menus[eidx].SetTitle(title);

	CBasePlayer@ dj = chan.getDj();
	bool isDjReserved = chan.isDjReserved();
	bool canDj = chan.canDj(plr);

	g_menus[eidx].AddItem("\\wHelp\\y", any("help"));
	g_menus[eidx].AddItem("\\wTurn off\\y", any("turn-off"));
	g_menus[eidx].AddItem("\\wChange channel\\y", any("channels"));
	g_menus[eidx].AddItem("\\w" + (canDj ? "Queue" : "Request") + " song" + "\\y", any("add-song"));
	g_menus[eidx].AddItem("\\w" + (canDj ? "Edit" : "View") + " queue  " + chan.getQueueCountString() + "\\y", any("edit-queue"));
	
	if (canDj) {
		bool isDj = dj !is null and dj.entindex() == plr.entindex();
		
		g_menus[eidx].AddItem("\\wSkip song\\y", any("skip-song"));
		g_menus[eidx].AddItem("\\w" + (isDj ? "Quit DJ" : "Become DJ") + "\\y", any("become-dj"));
		g_menus[eidx].AddItem("\\wInvite\\y", any("invite"));
	}
	
	string label = "\\wExit\\y";
	
	label += "\n\n\\yCurrent DJ:\n";
	if (dj !is null) {
		label += "\\w" + dj.pev.netname;
	} else if (isDjReserved) {
		int reserveTimeLeft = int(Math.Ceil(g_djReserveTime.GetInt() - g_Engine.time));
		label += "\\r(reserved for " + reserveTimeLeft + " seconds)";
	} else {
		label += "\\d(none)";
	}
	
	Song@ song = chan.queue.size() > 0 ? chan.queue[0] : null;
	
	label += "\n\n\\yNow Playing:\n";
	if (song !is null) {
		label += "\\w" + song.getName() + " \\d" + formatTime(chan.getTimeLeft());
		
		int diff = int(TimeDifference(state.tuneTime, chan.startTime).GetTimeDifference());
		
		if (diff > 0) {
			label += "\n\n\\r(desynced by " + diff + "+ seconds)\\d";
		}
		
	} else {
		label += "\\d(nothing)";
	}
	
	g_menus[eidx].AddItem(label + "\\d", any("exit"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(1, 0, plr);
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
	g_menus[eidx].SetTitle("\\y" + chan.name + " - " + title + "\\y\n" + g_rootPath.GetString() + prefix + "    ");	
	
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

void openMenuInviteRequest(EHandle h_plr, string asker, int channel, string keepOpenHud) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[channel];
	
	@g_menus[eidx] = CTextMenu(@callbackMenuRadio);
	g_menus[eidx].SetTitle("\\yYou're invited to listen to\nthe radio on " + g_channels[channel].name + "\n-" + asker + "\n");
	
	g_menus[eidx].AddItem("\\wAccept\\y", any("channel-" + channel));
	g_menus[eidx].AddItem("\\wDecline\\y", any(keepOpenHud.Length() > 0 ? keepOpenHud : "exit"));
	
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
	g_menus[eidx].AddItem("\\wCan't hear music?\\y", any("help-cant-hear"));
	g_menus[eidx].AddItem("\\wSong changing too soon?\\y", any("help-desync"));
	g_menus[eidx].AddItem("\\wTest installation\\y", any("test-install"));
	g_menus[eidx].AddItem("\\rDownload music pack\\y", any("download-pack"));
	//g_menus[eidx].AddItem("\\wRestart music\\y", any("restart-music"));
	//g_menus[eidx].AddItem("\\wShow command help?\\y", any("help-commands"));
	
	string label = "\\wRestart music\\y";
	label += "\n\nMusic pack last updated:\n\\w" + g_musicPackUpdateTime.GetString() + "\\y";
	
	g_menus[eidx].AddItem(label, any("restart-music"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
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
					
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n" + spos + ") " + listeners[i].pev.netname);
				}
				
				if (listeners.size() == 0) {
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n(empty)");
				}
			}
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n\n");
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