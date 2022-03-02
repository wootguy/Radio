void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

string formatTime(int totalSeconds) {
	int hours = totalSeconds / (60*60);
	int minutes = (totalSeconds / 60) - hours*60;
	int seconds = totalSeconds % 60;
	
	if (hours > 0) {
		string minStr = minutes >= 10 ? ("" + minutes) : ("0" + minutes);
		string secStr = seconds >= 10 ? ("" + seconds) : ("0" + seconds);
		return "" + hours + ":" + minStr + ":" + secStr + "";
	} else {
		string secStr = seconds >= 10 ? ("" + seconds) : ("0" + seconds);
		return "" + minutes + ":" + secStr + "";
	}
	
}

void clientCommand(CBaseEntity@ plr, string cmd, NetworkMessageDest destType=MSG_ONE) {
	NetworkMessage m(destType, NetworkMessages::NetworkMessageType(9), plr.edict());
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

// pick an entity to emit voice data from (must be a player slot or else it doesn't always work)
void updateVoiceSlotIdx() {
	int found = 0;
	for ( int i = 1; i <= g_Engine.maxClients; i++ ) {
		CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (p is null or !p.IsConnected()) {
			if (found == 0) {
				g_radio_ent_idx = i+1;
				found++;
			} else {
				g_voice_ent_idx = i+1;
				found++;
				return;
			}
		}
	}
	
	if (found == 0) {
		g_radio_ent_idx = 0;
		g_voice_ent_idx = 1;
	} else {
		g_voice_ent_idx = 0;
	}
}

void server_print(CBasePlayer@ plr, string msg) {
	g_EngineFuncs.ServerPrint(msg);
	g_Game.AlertMessage(at_logged, "\"%1<%2><%3><player>\" say \"%4\"\n", plr.pev.netname, string(g_EngineFuncs.GetPlayerUserId(plr.edict())), g_EngineFuncs.GetPlayerAuthId(plr.edict()), msg);
}

