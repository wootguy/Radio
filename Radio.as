// TODO:
// - hide menu if vote menu opens
// - more console commands
// - search for songs
// - kick inactive DJs (no song for long time)
// - cant exit channel menu
// - cant see who queued for 2nd song
// - messages are too spammy ("is now the dj spam")
// - is not the dj message not shown

const string SONG_FILE_PATH = "scripts/plugins/Radio/songs.txt";

CCVar@ g_rootPath;
CCVar@ g_musicPackUpdateTime;
CCVar@ g_musicPackVersionCheckFile;
CCVar@ g_musicPackLink;

CCVar@ g_inviteCooldown;
CCVar@ g_requestCooldown;
CCVar@ g_djReserveTime;
CCVar@ g_maxQueue;
CCVar@ g_channelCount;

dictionary g_player_states;
array<Channel> g_channels;
array<Song> g_songs; // values are Song
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
	string keepHudOpen = ""; // value is the menu type to open
	DateTime tuneTime; // last time player chose a channel (for displaying desync info)
	dictionary lastInviteTime; // for invite cooldowns per player and for \everyone
	float lastRequest; // for request cooldowns
	
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
			g_PlayerFuncs.SayText(plr, "[Radio] Wait " + waitTime + " seconds before inviting " + id + " again");
			return true;
		}
		
		return false;
	}
	
	bool shouldRequestCooldown(CBasePlayer@ plr) {	
		float delta = g_Engine.time - lastRequest;
		if (delta < g_requestCooldown.GetInt()) {			
			int waitTime = int((g_inviteCooldown.GetInt() - delta) + 0.99f);
			g_PlayerFuncs.SayText(plr, "[Radio] Wait " + waitTime + " seconds before requesting another song");
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
}

class FileNode {
	string name;
	Song@ file = null;
	array<FileNode@> children;
}

class Channel {
	string name;
	array<Song@> queue;
	string currentDj; // steam id
	DateTime startTime;
	bool shouldSkipSong = false;
	
	int getTimeLeft() {
		if (queue.size() > 0) {
			int diff = int(TimeDifference(DateTime(), startTime).GetTimeDifference());
			int songLen = (queue[0].lengthMillis + 999) / 1000;
			return songLen - diff;
		}
		
		return 0;
	}
	
	string getQueueCountString() {
		bool queueFull = int(queue.size()) > g_maxQueue.GetInt();
		string queueColor = queueFull ? "\\r" : "\\d";
		int queueSize = queue.size() > 0 ? (queue.size()-1) : 0;
		return queueColor + "(" + queueSize + " / " + g_maxQueue.GetInt() + ")";
	}
	
	CBasePlayer@ getDj() {
		return getPlayerByUniqueId(currentDj);
	}
	
	bool canDj(CBasePlayer@ plr) {
		CBasePlayer@ dj = getDj();
		return dj is null or dj.entindex() == plr.entindex();
	}
}

void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

string getPlayerUniqueId(CBasePlayer@ plr) {
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	
	if (steamId == 'STEAM_ID_LAN' or steamId == 'BOT') {
		steamId = plr.pev.netname;
	}
	
	return steamId;
}

CBasePlayer@ getPlayerByUniqueId(string id) {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		string steamid = getPlayerUniqueId(plr);
		if (steamid == id) {
			return plr;
		}
	}
	
	return null;
}

PlayerState@ getPlayerState(CBasePlayer@ plr)
{
	if (plr is null)
		return null;
		
	string steamId = getPlayerUniqueId(plr);
	
	if ( !g_player_states.exists(steamId) )
	{
		PlayerState state;
		g_player_states[steamId] = state;
	}
	
	return cast<PlayerState@>( g_player_states[steamId] );
}

void PluginInit()
{
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy" );
	
	g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @ClientJoin);
	g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @ClientLeave);
	g_Hooks.RegisterHook(Hooks::Player::ClientSay, @ClientSay);
	
	@g_rootPath = CCVar("rootPath", "mp3/radio/", "radio music root folder", ConCommandFlag::AdminOnly);
	@g_musicPackUpdateTime = CCVar("musicPackUpdateTime", "????-??-??", "music pack last updated time", ConCommandFlag::AdminOnly);
	@g_musicPackVersionCheckFile = CCVar("musicPackVersionCheckFile", "version_check/v1.mp3", "version check file (used in help menu)", ConCommandFlag::AdminOnly);
	@g_musicPackLink = CCVar("musicPackLink", "https://asdf.com/qwerty.zip", "music pack download link", ConCommandFlag::AdminOnly);
	
	@g_inviteCooldown = CCVar("inviteCooldown", 240, "Radio invite cooldown", ConCommandFlag::AdminOnly);
	@g_requestCooldown = CCVar("requestCooldown", 240, "Song request cooldown", ConCommandFlag::AdminOnly);
	@g_djReserveTime = CCVar("djReserveTime", 240, "Time to reserve DJ slots after level change", ConCommandFlag::AdminOnly);
	@g_maxQueue = CCVar("maxQueue", 8, "Max songs that can be queued", ConCommandFlag::AdminOnly);
	@g_channelCount = CCVar("channelCount", 4, "Number of available channels", ConCommandFlag::AdminOnly);
	
	g_channels.resize(g_channelCount.GetInt());
	
	for (uint i = 0; i < g_channels.size(); i++) {
		g_channels[i].name = "Channel " + (i+1);
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
	//g_Scheduler.SetInterval("radioResumeHack", 0.1f, -1);
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
		state.lastRequest = 0;
		state.keepHudOpen = ""; // prevent overflows while parsing game info
	}
}

HookReturnCode ClientJoin(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	string id = getPlayerUniqueId(plr);
	
	if (!g_level_changers.exists(id)) {
		if (state.channel >= 0) {
			if (g_channels[state.channel].queue.size() > 0) {
				Song@ song = g_channels[state.channel].queue[0];
				clientCommand(plr, getMp3PlayCommand(song.path));
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Now playing: " + song.getName() + "\n");
				state.tuneTime = DateTime();
			}
		}
		
		g_level_changers[id] = true;
	}
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientLeave(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	
	// TODO: this won't trigger for players who leave during level changes
	g_level_changers.delete(getPlayerUniqueId(plr));
	state.keepHudOpen = "";
	
	if (state.channel >= 0) {
		if (g_channels[state.channel].currentDj == getPlayerUniqueId(plr)) {
			g_channels[state.channel].currentDj = "";
		}
	}
	
	return HOOK_CONTINUE;
}

void addFileNode(string parentNodePath, string nodeName, Song@ song=null) {
	FileNode@ currentNode = g_root_folder;
	
	while (parentNodePath.Length() > 0) {
		int islash = int(parentNodePath.Find("/"));
		
		string nextDir = parentNodePath;
		
		if (islash != -1) {
			nextDir = parentNodePath.SubString(0, islash);
			parentNodePath = parentNodePath.SubString(islash+1);
		} else {
			parentNodePath = "";
		}
			
		bool found = false;
		for (uint i = 0; i < currentNode.children.size(); i++) {
			if (currentNode.children[i].name == nextDir) {
				@currentNode = @currentNode.children[i];
				found = true;
				break;
			}
		}
		
		if (!found) {
			FileNode newNode;
			newNode.name = nextDir;
			currentNode.children.insertLast(newNode);
			
			@currentNode = @newNode;
		}
	}
	
	FileNode newNode;
	newNode.name = nodeName;
	@newNode.file = @song;
	
	currentNode.children.insertLast(newNode);
}

FileNode@ getNodeFromPath(string path) {
	FileNode@ currentNode = g_root_folder;
	
	while (path.Length() > 0) {
		int islash = int(path.Find("/"));
		
		string nextDir = path;
		
		if (islash != -1) {
			nextDir = path.SubString(0, islash);
			path = path.SubString(islash+1);
		} else {
			path = "";
		}
			
		bool found = false;
		for (uint i = 0; i < currentNode.children.size(); i++) {
			if (currentNode.children[i].name == nextDir) {
				@currentNode = @currentNode.children[i];
				found = true;
				break;
			}
		}
		
		if (!found) {
			println("Node " + currentNode.name + " has no child " + nextDir);
			return null;
		}
	}
	
	return currentNode;
}

void loadSongs() {
	g_songs.resize(0);
	g_root_folder.children.resize(0);
	
	File@ file = g_FileSystem.OpenFile(SONG_FILE_PATH, OpenFile::READ);

	if (file !is null && file.IsOpen()) {
		while (!file.EOFReached()) {
			string line;
			file.ReadLine(line);
			
			if (line.IsEmpty())
				continue;
			
			array<string> parts = line.Split("|");

			Song song;
			song.path = parts[0];
			song.artist = parts[1];
			song.title = parts[2];
			song.lengthMillis = atoi(parts[3]);
			
			g_songs.insertLast(song);
			
			string fname = song.path;
			string parentDir = "";
			if (int(song.path.Find("/")) != -1) {
				parentDir = fname.SubString(0, fname.FindLastOf("/"));
				fname = fname.SubString(fname.FindLastOf("/")+1);
			}
			addFileNode(parentDir, fname, song);
		}

		file.Close();
	} else {
		g_Log.PrintF("[Radio] song list file not found: " + SONG_FILE_PATH + "\n");
	}
}

array<CBasePlayer@> getChannelListeners(int channel) {
	array<CBasePlayer@> listeners;
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		
		if (state.channel == channel) {
			listeners.insertLast(plr);
		}
	}
	
	return listeners;
}

void channelPrint(int channel, string msg, CBasePlayer@ exclude=null) {
	array<CBasePlayer@> listeners = getChannelListeners(channel);
	
	for (uint i = 0; i < listeners.size(); i++) {
		if (exclude is null or (listeners[i].entindex() != exclude.entindex())) {
			g_PlayerFuncs.ClientPrint(listeners[i], HUD_PRINTTALK, "[Radio] " + msg + "\n");
		}
	}
}

string getMp3PlayCommand(string songPath) {
	return "mp3 play " + g_rootPath.GetString() + songPath.Replace(".mp3", "");
}

void channelPlay(int channel, string songPath) {	
	channelCommand(channel, getMp3PlayCommand(songPath));
	g_channels[channel].startTime = DateTime();
}

void channelCommand(int channel, string cmd) {
	array<CBasePlayer@> listeners = getChannelListeners(channel);
	
	println("CHANNEL " + channel + " CMD: " + cmd);
	
	for (uint i = 0; i < listeners.size(); i++) {
		clientCommand(listeners[i], cmd);
	}
}

void clientCommand(CBaseEntity@ plr, string cmd) {
	NetworkMessage m(MSG_ONE, NetworkMessages::NetworkMessageType(9), plr.edict());
		m.WriteString(cmd);
	m.End();
}

void radioThink() {
	
	for (uint i = 0; i < g_channels.size(); i++) {
		bool isSongFinished = true;
		
		if (g_channels[i].queue.size() > 0) {
			int timeleft = g_channels[i].getTimeLeft();
			
			isSongFinished = timeleft <= 0;
			
			if (isSongFinished or g_channels[i].shouldSkipSong) {
				g_channels[i].queue.removeAt(0);
			}
		}
		
		if (isSongFinished or g_channels[i].shouldSkipSong) {
			g_channels[i].shouldSkipSong = false;
			
			if (g_channels[i].queue.size() > 0) {
				channelPrint(i, "Now playing: " + g_channels[i].queue[0].getName());
				channelPlay(i, g_channels[i].queue[0].path);
			}
		}
	}
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		
		if (state.keepHudOpen.Length() > 0) {
			g_Scheduler.SetTimeout(state.keepHudOpen, 0.0f, EHandle(plr));
		}
	}
}

void radioResumeHack() {	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		
		clientCommand(plr, "cd resume");
		
		if (state.keepHudOpen.Length() > 0) {
			g_Scheduler.SetTimeout(state.keepHudOpen, 0.0f, EHandle(plr));
		}
	}
}

void radioMenuCallback(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);
	
	state.keepHudOpen = "";

	string option = "";
	item.m_pUserData.retrieve(option);
	
	string chanPrefix = "channel-";
	
	bool canDj = true;
	if (state.channel >= 0) {
		canDj = g_channels[state.channel].canDj(plr);
	}
	
	if (option == "channels") {
		g_Scheduler.SetTimeout("openChannelMenu", 0.0f, EHandle(plr));
	}
	else if (option == "turn-off") {
		if (state.channel >= 0) {
			if (g_channels[state.channel].currentDj == getPlayerUniqueId(plr)) {
				g_channels[state.channel].currentDj = "";
				channelPrint(state.channel, "" + plr.pev.netname + " tuned out and is not the DJ anymore.", plr);
			} else {
				channelPrint(state.channel, "" + plr.pev.netname + " tuned out.", plr);
			}
		}
		
		state.channel = -1;
		
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Turned off.\n");
		clientCommand(plr, "mp3 stop");
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openRadioMenu", 0.0f, EHandle(plr));
	}
	else if (option.Find(chanPrefix) == 0) {
		int oldChannel = state.channel;
		state.channel = atoi(option.SubString(chanPrefix.Length()));
		
		g_Scheduler.SetTimeout("openRadioMenu", 0.0f, EHandle(plr));
		
		if (oldChannel == state.channel) {
			return;
		}
		
		if (oldChannel >= 0) {
			if (g_channels[oldChannel].currentDj == getPlayerUniqueId(plr)) {
				g_channels[oldChannel].currentDj = "";
				channelPrint(oldChannel, "" + plr.pev.netname + " tuned out and is not the DJ anymore.", plr);
			} else {
				channelPrint(oldChannel, "" + plr.pev.netname + " tuned out.", plr);
			}
		}
		
		if (g_channels[state.channel].queue.size() > 0) {
			clientCommand(plr, getMp3PlayCommand(g_channels[state.channel].queue[0].path));
		} else {
			clientCommand(plr, "mp3 stop");
		}
		
		channelPrint(state.channel, "" + plr.pev.netname + " tuned in.", plr);
		state.tuneTime = DateTime();
		
	}
	else if (option == "add-song") {
		g_Scheduler.SetTimeout("openSongMenu", 0.0f, EHandle(plr), "", 0);
	}
	else if (option.Find("search:") == 0) {
		string path = option.Length() > 7 ? option.SubString(7) : "";
		g_Scheduler.SetTimeout("openSongMenu", 0.0f, EHandle(plr), path, 0);
	}
	else if (option.Find("play:") == 0) {
		array<string> parts = option.Split(":");
		int page = atoi(parts[1]);
		string path = parts[2];
		string parentPath = "";
		
		int islash = path.FindLastOf("/");
		if (islash != -1) {
			parentPath = path.SubString(0, islash);
		}
		
		Song@ song = getNodeFromPath(path).file;
		
		if (!canDj)  {
			if (!state.shouldRequestCooldown(plr)) {
				state.lastRequest = g_Engine.time;
				string helpPath = parentPath;
				if (helpPath.Length() > 0) {
					helpPath += "/";
				}
				channelPrint(state.channel, "" + plr.pev.netname + " requested: " + helpPath + song.getName());
			}
		}
		else if (int(g_channels[state.channel].queue.size()) > g_maxQueue.GetInt()) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Queue is full!\n");
		}
		else {
		
			if (g_channels[state.channel].queue.size() == 0) {
				channelPlay(state.channel, song.path);
				if (g_channels[state.channel].currentDj.Length() == 0) {
					channelPrint(state.channel, "" + plr.pev.netname + " queued: " + song.getName());
				} else {
					channelPrint(state.channel, "Now playing: " + song.getName());
				}
			}
			
			g_channels[state.channel].queue.insertLast(song);
		}
		
		g_Scheduler.SetTimeout("openSongMenu", 0.0f, EHandle(plr), parentPath, page);
	}
	else if (option == "skip-song") {
		if (!canDj) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Only the DJ can skip songs.\n");
			g_Scheduler.SetTimeout("openRadioMenu", 0.0f, EHandle(plr));
			return;
		}
		
		if (g_channels[state.channel].queue.size() == 0) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] No song is playing.\n");
		}
		else {
			channelPrint(state.channel, "Song was skipped");
			g_channels[state.channel].shouldSkipSong = true;
		}
		
		g_Scheduler.SetTimeout("openRadioMenu", 0.0f, EHandle(plr));
	}
	else if (option == "become-dj") {
		CBasePlayer@ currentDj = g_channels[state.channel].getDj();
		
		if (currentDj !is null) {
			if (currentDj.entindex() != plr.entindex()) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] " + currentDj.pev.netname + " must stop DJ'ing first.\n");
			} else {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] " + currentDj.pev.netname + " is not the DJ anymore.\n");
				g_channels[state.channel].currentDj = "";
			}
		} else {
			g_channels[state.channel].currentDj = getPlayerUniqueId(plr);
			channelPrint(state.channel, "" + plr.pev.netname + " is now the DJ!");
		}
		
		g_Scheduler.SetTimeout("openRadioMenu", 0.0f, EHandle(plr));
	}
	else if (option == "invite") {		
		g_Scheduler.SetTimeout("openInviteMenu", 0.0f, EHandle(plr));
	}
	else if (option == "inviteall") {
		int inviteCount = 0;
	
		if (state.shouldInviteCooldown(plr, "\\everyone")) {
			g_Scheduler.SetTimeout("openRadioMenu", 0.0f, EHandle(plr));
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
			
			g_Scheduler.SetTimeout("openInviteRequestMenu", 0.5f, EHandle(target), "" + plr.pev.netname, state.channel, targetState.keepHudOpen);
			targetState.keepHudOpen = "";
			inviteCount++;
		}
		
		if (inviteCount == 0) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] No one to invite.\n");
		}
		else {
			state.lastInviteTime["\\everyone"] = g_Engine.time;
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Invitations sent to " + inviteCount + " players.\n");
		}

		g_Scheduler.SetTimeout("openRadioMenu", 0.0f, EHandle(plr));
	}
	else if (option.Find("invite-") == 0) {
		string targetId = option.SubString(7);
		CBasePlayer@ target = getPlayerByUniqueId(targetId);
		
		if (state.shouldInviteCooldown(plr, targetId)) {
			g_Scheduler.SetTimeout("openRadioMenu", 0.0f, EHandle(plr));
			return;
		}
		
		if (target !is null) {
			PlayerState@ targetState = getPlayerState(target);
			g_Scheduler.SetTimeout("openInviteRequestMenu", 0.5f, EHandle(target), "" + plr.pev.netname, state.channel, targetState.keepHudOpen);
			targetState.keepHudOpen = "";
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Invitation sent to " + target.pev.netname + "\n");
			
			state.lastInviteTime[targetId] = g_Engine.time;
		} else {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Invitation failed. Player left the game.\n");
		}
		
		g_Scheduler.SetTimeout("openRadioMenu", 0.0f, EHandle(plr));
	}
	else if (option.Find("invite-decline-") == 0) {
		g_Scheduler.SetTimeout("openRadioMenu", 0.0f, EHandle(plr));
	}
	else if (option == "restart-music") {
		if (g_channels[state.channel].queue.size() > 0) {
			Song@ song = g_channels[state.channel].queue[0];
			clientCommand(plr, getMp3PlayCommand(song.path));
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Now playing: " + song.getName());
			state.tuneTime = DateTime();
		} else {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] There is no music playing on " + g_channels[state.channel].name + "\n");
		}
		g_Scheduler.SetTimeout("openHelpMenu", 0.0f, EHandle(plr));
	}
	else if (option == "download-pack") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Download link is below. You can copy it from the console.\n\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, g_musicPackLink.GetString() + "\n\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Extract to Steam/Common/Sven Co-op/svencoop_downloads/\n");
		
		
		g_Scheduler.SetTimeout("openHelpMenu", 0.0f, EHandle(plr));
	}
	else if (option == "help") {
		g_Scheduler.SetTimeout("openHelpMenu", 0.0f, EHandle(plr));
	}
	else if (option == "help-cant-hear") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Can't hear music?\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "  1) Download and install the latest music pack\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "  2) Pick \"Test installation\" to test your installation\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "  3) Check that your music volume isn't too low in Options -> Audio\n");
		g_Scheduler.SetTimeout("openHelpMenu", 0.0f, EHandle(plr));
	}
	else if (option == "help-desync") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Song changing too soon?\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "  Your music playback was desynced from the server. There are a few causes for this:\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "    - You joined a channel after the music started (you'll see red desync text in this case)\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "    - You alt-tabbed out of the game (music pauses when the game isn't in focus)\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "    - Your game or PC was frozen for a few seconds\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "  To fix the desync, just wait for the next song to start and keep the game window in focus.\n");
		g_Scheduler.SetTimeout("openHelpMenu", 0.0f, EHandle(plr));
	}
	else if (option == "help-commands") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Command help was sent to your console.\n");
		g_Scheduler.SetTimeout("openHelpMenu", 0.0f, EHandle(plr));
	}
	else if (option == "test-install") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] You should be hearing a text-to-speech voice now. If not, increase your music volume in Options -> Audio\n");
		clientCommand(plr, getMp3PlayCommand(g_musicPackVersionCheckFile.GetString()));
		g_Scheduler.SetTimeout("openHelpMenu", 0.0f, EHandle(plr));
	}
}

void openRadioMenu(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[state.channel]; // TODO: invalid index somehow
	
	state.keepHudOpen = "openRadioMenu";
	
	string title = "\\y" + chan.name;
	title += "  \\d(" + getChannelListeners(state.channel).size() + " listening)\\y";
	
	@g_menus[eidx] = CTextMenu(@radioMenuCallback);
	g_menus[eidx].SetTitle(title);

	CBasePlayer@ dj = chan.getDj();
	bool isDjReserved = dj is null and chan.currentDj.Length() > 0 and g_Engine.time < g_djReserveTime.GetInt();
	bool canDj = chan.canDj(plr) and !isDjReserved;

	g_menus[eidx].AddItem("\\wHelp\\y", any("help"));
	g_menus[eidx].AddItem("\\wTurn off\\y", any("turn-off"));
	g_menus[eidx].AddItem("\\wChange channel\\y", any("channels"));
	
	if (canDj) {
		g_menus[eidx].AddItem("\\wQueue song  " + chan.getQueueCountString() + "\\y", any("add-song"));
	} else {
		g_menus[eidx].AddItem("\\wRequest song\\y", any("add-song"));
	}
	
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

void openChannelMenu(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	
	state.keepHudOpen = "openChannelMenu";
	
	@g_menus[eidx] = CTextMenu(@radioMenuCallback);
	g_menus[eidx].SetTitle("\\yRadio Channels\n");
	
	for (uint i = 0; i < g_channels.size(); i++) {
		string label = "\\w" + g_channels[i].name;
		
		array<CBasePlayer@> listeners = getChannelListeners(i);
		
		CBasePlayer@ dj = g_channels[i].getDj();
		
		if (listeners.size() > 0) {			
			label += "\\d  (" + listeners.size() + " listening)";
		}
		
		Song@ song = g_channels[i].queue.size() > 0 ? g_channels[i].queue[0] : null;
		label += "\n\\y      Current DJ:\\w " + (dj !is null ? string(dj.pev.netname) : "\\d(none)");
		label += "\n\\y      Now Playing:\\w " + (song !is null ? song.getName() + " \\d" + formatTime(g_channels[i].getTimeLeft()) : "\\d(nothing)");
		
		label += "\n\\y";
		
		g_menus[eidx].AddItem(label, any("channel-" + i));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(1, 0, plr);
}

string formatTime(int totalSeconds) {
	int minutes = totalSeconds / 60;
	int seconds = totalSeconds % 60;
	string secStr = seconds >= 10 ? ("" + seconds) : ("0" + seconds);
	return "(" + minutes + ":" + secStr + ")";
}

void openSongMenu(EHandle h_plr, string path, int page) {
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
	
	@g_menus[eidx] = CTextMenu(@radioMenuCallback);
	g_menus[eidx].SetTitle("\\y" + chan.name + " - " + title + "\\y\n" + g_rootPath.GetString() + prefix + "    ");	
	
	FileNode@ node = getNodeFromPath(path);
	
	string upCommand = "main-menu";
	
	if (path != "") {
		string upDir = "";
		int islash = path.FindLastOf("/");
		if (islash != -1) {
			upDir = path.SubString(0, islash);
		}
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

void openInviteRequestMenu(EHandle h_plr, string asker, int channel, string keepOpenHud)
{
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[channel];
	
	@g_menus[eidx] = CTextMenu(@radioMenuCallback);
	g_menus[eidx].SetTitle("\\yYou're invited to listen to\nthe radio on " + g_channels[channel].name + "\n-" + asker + "\n");
	
	g_menus[eidx].AddItem("\\wAccept\\y", any("channel-" + channel));
	g_menus[eidx].AddItem("\\wDecline\\y", any(keepOpenHud.Length() > 0 ? keepOpenHud : "exit"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openInviteMenu(EHandle h_plr)
{
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[state.channel];
	
	@g_menus[eidx] = CTextMenu(@radioMenuCallback);
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

void openHelpMenu(EHandle h_plr)
{
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	
	@g_menus[eidx] = CTextMenu(@radioMenuCallback);
	g_menus[eidx].SetTitle("\\yRadio Help");
	
	g_menus[eidx].AddItem("\\w..\\y", any("main-menu"));
	g_menus[eidx].AddItem("\\wCan't hear music?\\y", any("help-cant-hear"));
	g_menus[eidx].AddItem("\\wSong changing too soon?\\y", any("help-desync"));
	g_menus[eidx].AddItem("\\wTest installation\\y", any("test-install"));
	g_menus[eidx].AddItem("\\wDownload music pack\\y", any("download-pack"));
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
		bool isEnabled = state.channel >= 0;
	
		if (isEnabled) {
			openRadioMenu(EHandle(plr));
		} else {
			openChannelMenu(EHandle(plr));
		}
		
		
		return true;
	}
	
	return false;
}

HookReturnCode ClientSay( SayParameters@ pParams ) {
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	if (doCommand(plr, args, false))
	{
		pParams.ShouldHide = true;
		return HOOK_CONTINUE;
	}
	return HOOK_CONTINUE;
}

CClientCommand _ghost("radio", "radio commands", @consoleCmd );

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}