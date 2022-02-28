#include "FakeMic"

void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

dictionary g_player_states;
string voice_server_file = "scripts/plugins/store/_tovoice.txt";
const float BUFFER_DELAY = 0.7f; // minimum time for a voice packet to reach players (seems to actually be 4x longer...)

class PlayerState {
	bool isBot = false; // send bot commands to this player?
	bool ttsEnabled = true;
	bool isListening = true;
	bool isDebugging = true;
	string lang = "en";
	int pitch = 100;
}

dictionary g_langs = {
	{"af", "African"},
	{"sq", "Albanian"},
	{"ar", "Arabic"},
	{"hy", "Armenian"},
	{"bn", "Bengali"},
	{"bs", "Bosnian"},
	{"bg", "Bulgarian"},
	{"ct", "Catalan"},
	{"hr", "Croatian"},
	{"cs", "Czech"},
	{"da", "Danish"},
	{"nl", "Dutch"},
	{"au", "English (Austrailia)"},
	{"ca", "English (Canada)"},
	{"in", "English (India)"},
	{"ir", "English (Ireland)"},
	{"afs", "English (South Africa)"},
	{"ek", "English (United Kingdom)"},
	{"en", "English (United States)"},
	{"eo", "Esperanto"},
	{"et", "Estonian"},
	{"tl", "Filipino"},
	{"fi", "Finnish"},
	{"fc", "French (Canada)"},
	{"fr", "French (France)"},
	{"de", "German"},
	{"el", "Greek"},
	{"hi", "Hindi"},
	{"hu", "Hungarian"},
	{"is", "Icelandic"},
	{"id", "Indonesian"},
	{"it", "Italian"},
	{"ja", "Japanese"},
	{"jw", "Javanese"},
	{"kn", "Kannada"},
	{"km", "Khmer"},
	{"ko", "Korean"},
	{"la", "Latin"},
	{"lv", "Latvian"},
	{"mk", "Macedonian"},
	{"cn", "Mandarin (China Mainland)"},
	{"tw", "Mandarin (Taiwan)"},
	//{"my","Myanmar (Burmese)"},
	{"ne", "Nepali"},
	{"no", "Norwegian"},
	{"pl", "Polish"},
	{"br", "Portuguese (Brazil)"},
	{"pt", "Portuguese (Portugal)"},
	{"ro", "Romanian"},
	{"ru", "Russian"},
	{"mx", "Spanish (Mexico)"},
	{"es", "Spanish (Spain)"},
	{"ma", "Spanish (United States)"},
	{"sr", "Serbian"},
	{"si", "Sinhala"},
	{"sk", "Slovak"},
	{"su", "Sundanese"},
	{"sw", "Swahili"},
	{"sv", "Swedish"},
	{"ta", "Tamil"},
	{"te", "Telugu"},
	{"th", "Thai"},
	{"tr", "Turkish"},
	{"uk", "Ukrainian"},
	{"ur", "Urdu"},
	{"vi", "Vietnamese"},
	{"cy", "Welsh"}
};

PlayerState@ getPlayerState(CBasePlayer@ plr)
{
	if (plr is null or !plr.IsConnected())
		return null;
		
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN' or steamId == 'BOT') {
		steamId = plr.pev.netname;
	}
	
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
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy/" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook( Hooks::Player::ClientPutInServer, @ClientJoin );
	
	//g_Scheduler.SetInterval("stopsound_fix", 3.0f, -1);
	
	g_voice_ent_idx = getEmptyPlayerSlotIdx();
	load_samples();
	play_samples(false);
}

void MapInit() {
	File@ file = g_FileSystem.OpenFile( voice_server_file, OpenFile::APPEND );
	file.Write( null );
	file.Close();
}

void clientCommand(CBaseEntity@ plr, string cmd, NetworkMessageDest destType=MSG_ONE) {
	NetworkMessage m(destType, NetworkMessages::NetworkMessageType(9), plr.edict());
		// surround with ; to prevent multiple commands being joined when sent in the same frame(?)
		// this fixes music sometimes not loading/starting/stopping
		m.WriteString(";" + cmd + ";");
	m.End();
}

void stopsound_fix() {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		clientCommand(plr, "stopsound", MSG_ONE_UNRELIABLE);
	}
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args, string chatText, bool inConsole) {
	bool isAdmin = g_PlayerFuncs.AdminLevel(plr) >= ADMIN_YES;
	PlayerState@ state = getPlayerState(plr);
	
	if (args.ArgC() >= 1)
	{
		if (args[0] == ".micbot" || args[0] == ".mhelp") {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "MicBot commands sent to your console.\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "MicBot reads messages aloud and can play audio from youtube links.\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    ~<message>        = Hide your message from the chat.\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    .mmute            = Mute MicBot audio for yourself\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    .mpitch <1-200>   = Set your text-to-speech pitch.\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    .mlang <language> = Set your text-to-speech language.\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    .mlangs           = List valid languages.\n");			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    .mstop            = Stop current audio for everyone.\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    .mstop speak      = Stop current text-to-speech audio.\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    .mstop last       = Stop current youtube videos except the one that first started playing.\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    .mstop first      = Stop current youtube videos except the one that last started playing.\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    .mtts             = Enable/Disable text to speech for your messages.\n");
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    You can add a timestamp after a youtube link to play at an offset. For example:\n");
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    https://www.youtube.com/watch?v=b8HO6hba9ZE 0:27\n");
			return true; // hide from chat relay
		}
		else if (args[0] == ".mlangs") {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Language codes sent to your console.\n");
			
			array<string>@ langKeys = g_langs.getKeys();
			array<string> lines;
			
			langKeys.sort(function(a,b) { return string(g_langs[a]) < string(g_langs[b]); });
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "Valid language codes:\n");
			for (uint i = 0; i < g_langs.size(); i++) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "    " + langKeys[i] + " = " + string(g_langs[langKeys[i]]) + "\n");
			}
			
			return true; // hide from chat relay
		}
		if (args[0] == ".mtts") {
			state.ttsEnabled = !state.ttsEnabled;
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Your text to speech is " + (state.ttsEnabled ? "enabled" : "disabled") + ".\n");
			return true;
		} else if (args[0] == ".mmute") {		
			state.isListening = !state.isListening;
			
			if (state.isListening) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Unmuted.\n");
			} else {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Muted.\n");
			}

			return true;
		} else if (args[0] == ".mdebug") {		
			state.isDebugging = !state.isDebugging;
			
			if (state.isDebugging) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Debug mode ON.\n");
			} else {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Debug mode OFF.\n");
			}

			return true;
		}
		else if (args[0] == '.mbuffer') {
			if (!isAdmin) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Admins only.\n");
				return true;
			}
			
			ideal_buffer_size = atoi(args[1]);
			g_packet_stream.resize(0);
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Ideal buffer size set to " + ideal_buffer_size + ".\n");
			return true;
		}
		else if (args[0] == '.mstop') {
			string msg = "[MicBot] " + plr.pev.netname + ": " + args[0] + " " + args[1] + "\n";
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTNOTIFY, msg);
			server_print(plr, msg);
			message_bots(plr, args[0] + " " + args[1]);
			return true; // hide from chat relay
		}
		else if (args[0] == '.mlang') {
			string code = args[1].ToLowercase();
			
			if (g_langs.exists(code)) {
				state.lang = code;
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Language set to " + string(g_langs[code]) + ".\n");
			} else {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Invalid language code \"" + code + "\". Type \".mlangs\" for a list of valid codes.\n");
			}
			
			return true; // hide from chat relay
		}
		else if (args[0] == '.mpitch') {
			int pitch = atoi(args[1]);
			
			if (pitch < 10) {
				pitch = 10;
			} else if (pitch > 200) {
				pitch = 200;
			}
			
			state.pitch = pitch;
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[MicBot] Pitch set to " + pitch + ".\n");
			
			return true; // hide from chat relay
		}
		else if (state.ttsEnabled and chatText.Length() > 0 and chatText.SubString(0,3).ToLowercase() != "/me") {		
			message_bots(plr, chatText);
		}
		
		if (args[0][0] == "~") {
			string msg = "[MicBot] " + plr.pev.netname + ": " + chatText + "\n";
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTCONSOLE, msg);
			server_print(plr, msg);
			return true; // hide from chat relay
		}
	}
	
	return false;
}

void server_print(CBasePlayer@ plr, string msg) {
	g_EngineFuncs.ServerPrint(msg);
	g_Game.AlertMessage(at_logged, "\"%1<%2><%3><player>\" say \"%4\"\n", plr.pev.netname, string(g_EngineFuncs.GetPlayerUserId(plr.edict())), g_EngineFuncs.GetPlayerAuthId(plr.edict()), msg);
}

void message_bots(CBasePlayer@ sender, string text) {
	PlayerState@ state = getPlayerState(sender);
	string msg = "" + sender.pev.netname + "\\" + state.lang + "\\" + state.pitch + "\\" + text + "\n";
	send_voice_server_message(msg);
}

void send_voice_server_message(string msg) {
	File@ file = g_FileSystem.OpenFile( voice_server_file, OpenFile::APPEND );
	
	if (!file.IsOpen()) {
		string text = "[MicBot] Failed to open: " + voice_server_file + "\n";
		println(text);
		g_Log.PrintF(text);
		return;
	}
	
	file.Write(msg);
	file.Close();
}

void send_debug_message(string msg) {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		if (state.isDebugging) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, msg);
		}
	}
}

void send_notification(string msg, bool chatNotNotification) {
	g_Scheduler.SetTimeout("send_notification_delay", BUFFER_DELAY, msg, chatNotNotification);
}

void send_notification_delay(string msg, bool chatNotNotification) {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		if (state.isListening and chatNotNotification) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, msg);
		} else {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTNOTIFY, msg);
		}
	}
}

HookReturnCode ClientSay( SayParameters@ pParams ) {
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	
	if (pParams.ShouldHide) {
		return HOOK_CONTINUE;
	}
	
	if (args.ArgC() > 0 && doCommand(plr, args, pParams.GetCommand(), false))
	{
		pParams.ShouldHide = true;
		return HOOK_HANDLED;
	}
	return HOOK_CONTINUE;
}

CClientCommand _g("micbot", "Spectate commands", @consoleCmd );
CClientCommand _g2("mlangs", "Spectate commands", @consoleCmd );
CClientCommand _g3("mtts", "Spectate commands", @consoleCmd );
CClientCommand _g4("mstop", "Spectate commands", @consoleCmd );
CClientCommand _g5("mlang", "Spectate commands", @consoleCmd );
CClientCommand _g6("mpitch", "Spectate commands", @consoleCmd );
CClientCommand _g7("mhelp", "Spectate commands", @consoleCmd );
CClientCommand _g8("mmute", "Spectate commands", @consoleCmd );
CClientCommand _g9("mdebug", "Spectate commands", @consoleCmd );

void consoleCmd( const CCommand@ args ) {
	string chatText = "";
	
	for (int i = 0; i < args.ArgC(); i++) {
		chatText += args[i] + " ";
	}
	
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, chatText, true);
}