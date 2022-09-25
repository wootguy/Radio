#include "meta_util.h"

void ClientCommand(edict_t* pEntity);

void PluginInit(plugin_info_t* info) {
	info->name = "Radio";
	info->version = "1.0";
	info->author = "w00tguy";
	info->url = "https://github.com/wootguy";

	g_dll_hooks.pfnClientCommand = ClientCommand;

	ALERT(at_console, "Hello from RADIO WOPW UPDATe!!!!\n");
}

void ClientCommand(edict_t* pEntity) {
	ALERT(at_console, "name=%s (%d), cmd='%s %s'\n", STRING(pEntity->v.netname), pEntity->v.flags, CMD_ARGV(0), CMD_ARGC() >= 1 ? CMD_ARGS() : "");
	//ALERT(at_console, "got dll client command\n");
	RETURN_META(MRES_IGNORED);
}