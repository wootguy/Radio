void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

string formatTime(int totalSeconds) {
	int minutes = totalSeconds / 60;
	int seconds = totalSeconds % 60;
	string secStr = seconds >= 10 ? ("" + seconds) : ("0" + seconds);
	return "(" + minutes + ":" + secStr + ")";
}

void clientCommand(CBaseEntity@ plr, string cmd) {
	NetworkMessage m(MSG_ONE, NetworkMessages::NetworkMessageType(9), plr.edict());
		// surround with ; to prevent multiple commands being joined when sent in the same frame(?)
		// this fixes music sometimes not loading/starting/stopping
		m.WriteString(";" + cmd + ";");
	m.End();
}

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

PlayerState@ getPlayerState(CBasePlayer@ plr) {
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

string getParentFolder(string fullPath) {
	string parentPath = "";
		
	int islash = fullPath.FindLastOf("/");
	if (islash != -1) {
		parentPath = fullPath.SubString(0, islash);
	}
	
	return parentPath;
}