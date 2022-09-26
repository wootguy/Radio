#include "radio.h"
#include <string>
#include "enginecallback.h"
#include "eiface.h"
#include "radio_utils.h"
#include "TextMenu.h"

using namespace std;

cvar_t* g_inviteCooldown = NULL;

map<string, PlayerState*> g_player_states;

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

void PluginInit() {
	g_dll_hooks.pfnClientCommand = ClientCommand;
	g_dll_hooks.pfnServerActivate = MapInit;
	g_dll_hooks.pfnStartFrame = StartFrame;
	g_dll_hooks.pfnClientPutInServer = ClientJoin;

	g_engine_hooks.pfnMessageBegin = MessageBegin;
	
	g_inviteCooldown = RegisterCVar("radio.inviteCooldown", "0", 0, 0);
	
	g_scheduler.setInterval(radioThink, 0.5f, -1);

	println("Hello from RADIO WOPW UPDATe!!!!");
}

void MessageBegin(int msg_dest, int msg_type, const float* pOrigin, edict_t* ed) {
	TextMenuMessageBeginHook(msg_dest, msg_type, pOrigin, ed);
	RETURN_META(MRES_IGNORED);
}

void radioThink() {
	//println("IM THOOONKING");
	for (int i = 1; i < gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);
		if (ent && (ent->v.flags & FL_CLIENT)) {
			string authid = (*g_engfuncs.pfnGetPlayerAuthId)(ent);
			println("SLOT %d: %s", i, authid.c_str());
		}
	}
}

void PluginExit() {
	println("ZOMG RADIO UINLOADING");
}

void MapInit(edict_t* pEdictList, int edictCount, int clientMax) {
	println("ZOMG MAP INIT~~~~~~~~~~~~~~~~");
}

void ClientJoin(edict_t* pEntity) {
	string authid = (*g_engfuncs.pfnGetPlayerAuthId)(pEntity);

	PlayerState* state = getPlayerState(authid);

	println("ZOMG SOMEONE JOINED WITH ID: %s and %d", authid, state->playAfterFullyLoaded);
}

void StartFrame() {
	g_scheduler.think();
}

void logClientCommand(edict_t* pEntity) {
	string command = CMD_ARGV(0);

	for (int i = 1; i < CMD_ARGC(); i++) {
		command += string(" ") + CMD_ARGV(i);
	}

	println("[cmd] %s: '%s'", STRING(pEntity->v.netname), command.c_str());
}

void menuCallback(edict_t* pEntity, int iSelect, string option) {
	ClientPrint(&pEntity->v, HUD_PRINTNOTIFY, "ZOMG CHOSE %s", option.c_str());
}

void ClientCommand(edict_t* pEntity) {
	TextMenuClientCommandHook(pEntity);

	int entindex = ENTINDEX(pEntity);

	bool isSayCommand = false;
	string command = CMD_ARGV(0);

	if (toLowerCase(CMD_ARGV(0)) == "say") {
		isSayCommand = true;
		command = CMD_ARGV(1);
	}

	command = toLowerCase(command);

	META_RES ret = MRES_IGNORED;

	if (command == "radio") {
		TextMenu& menu = initMenuForPlayer(pEntity, menuCallback);
		menu.setTitle("TEST MENU");
		menu.addOption("TEST");
		menu.addOption("TEST");
		menu.openMenu(pEntity, 10);

		hudtextparms_t params = { 0 };
		params.fadeoutTime = 0.5f;
		params.holdTime = 1.0f;
		params.r1 = 255;
		params.g1 = 255;
		params.b1 = 255;
		params.x = -1;
		params.y = 0.0001f;
		params.channel = 2;

		UTIL_HudMessage(pEntity, params, "Hello test");

		ret = MRES_SUPERCEDE;
	}

	logClientCommand(pEntity);

	RETURN_META(ret);
}