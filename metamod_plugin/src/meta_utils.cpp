#include "meta_utils.h"
#include "radio_utils.h"
#include <chrono>

Scheduler g_Scheduler = Scheduler();
const char* ADMIN_LIST_FILE = "svencoop/admins.txt";

map<string, int> g_admins;

string toLowerCase(string str) {
	string out = str;

	for (int i = 0; str[i]; i++) {
		out[i] = tolower(str[i]);
	}

	return out;
}

#define MAX_CVARS 32

cvar_t g_cvar_data[MAX_CVARS];
int g_cvar_count = 0;

cvar_t* RegisterCVar(char* name, char* strDefaultValue, int intDefaultValue, int flags) {
	
	if (g_cvar_count >= MAX_CVARS) {
		println("Failed to add cvar '%s'. Increase MAX_CVARS and recompile.", name);
		return NULL;
	}

	g_cvar_data[g_cvar_count].name = name;
	g_cvar_data[g_cvar_count].string = strDefaultValue;
	g_cvar_data[g_cvar_count].flags = flags | FCVAR_EXTDLL;
	g_cvar_data[g_cvar_count].value = intDefaultValue;
	g_cvar_data[g_cvar_count].next = NULL;

	CVAR_REGISTER(&g_cvar_data[g_cvar_count]);

	g_cvar_count++;

	return CVAR_GET_POINTER(name);
}

//
// Funcs copied from HLSDK
//

void ClientPrintAll(int msg_dest, const char* msg_name, const char* param1, const char* param2, const char* param3, const char* param4)
{
	MESSAGE_BEGIN(MSG_ALL, MSG_TextMsg);
	WRITE_BYTE(msg_dest);
	WRITE_STRING(msg_name);

	if (param1)
		WRITE_STRING(param1);
	if (param2)
		WRITE_STRING(param2);
	if (param3)
		WRITE_STRING(param3);
	if (param4)
		WRITE_STRING(param4);

	MESSAGE_END();
}

void ClientPrint(edict_t* client, int msg_dest, const char* msg_name, const char* param1, const char* param2, const char* param3, const char* param4)
{
	MESSAGE_BEGIN(MSG_ONE, MSG_TextMsg, NULL, client);
	WRITE_BYTE(msg_dest);
	WRITE_STRING(msg_name);

	if (param1)
		WRITE_STRING(param1);
	if (param2)
		WRITE_STRING(param2);
	if (param3)
		WRITE_STRING(param3);
	if (param4)
		WRITE_STRING(param4);

	MESSAGE_END();
}

unsigned short FixedUnsigned16(float value, float scale)
{
	int output;

	output = value * scale;
	if (output < 0)
		output = 0;
	if (output > 0xFFFF)
		output = 0xFFFF;

	return (unsigned short)output;
}

short FixedSigned16(float value, float scale)
{
	int output;

	output = value * scale;

	if (output > 32767)
		output = 32767;

	if (output < -32768)
		output = -32768;

	return (short)output;
}

// modified to not use CBaseEntity or loop through players to send individual messages
void HudMessage(edict_t* pEntity, const hudtextparms_t& textparms, const char* pMessage, int dest)
{
	if (dest == -1) {
		dest = pEntity ? MSG_ONE : MSG_ALL;
	}

	MESSAGE_BEGIN(dest, SVC_TEMPENTITY, NULL, pEntity);
	WRITE_BYTE(TE_TEXTMESSAGE);
	WRITE_BYTE(textparms.channel & 0xFF);

	WRITE_SHORT(FixedSigned16(textparms.x, 1 << 13));
	WRITE_SHORT(FixedSigned16(textparms.y, 1 << 13));
	WRITE_BYTE(textparms.effect);

	WRITE_BYTE(textparms.r1);
	WRITE_BYTE(textparms.g1);
	WRITE_BYTE(textparms.b1);
	WRITE_BYTE(textparms.a1);

	WRITE_BYTE(textparms.r2);
	WRITE_BYTE(textparms.g2);
	WRITE_BYTE(textparms.b2);
	WRITE_BYTE(textparms.a2);

	WRITE_SHORT(FixedUnsigned16(textparms.fadeinTime, 1 << 8));
	WRITE_SHORT(FixedUnsigned16(textparms.fadeoutTime, 1 << 8));
	WRITE_SHORT(FixedUnsigned16(textparms.holdTime, 1 << 8));

	if (textparms.effect == 2)
		WRITE_SHORT(FixedUnsigned16(textparms.fxTime, 1 << 8));

	if (strlen(pMessage) < 512)
	{
		WRITE_STRING(pMessage);
	}
	else
	{
		char tmp[512];
		strncpy(tmp, pMessage, 511);
		tmp[511] = 0;
		WRITE_STRING(tmp);
	}
	MESSAGE_END();
}

void HudMessageAll(const hudtextparms_t& textparms, const char* pMessage, int dest)
{
	HudMessage(NULL, textparms, pMessage, dest);
}

void LoadAdminList() {
	g_admins.clear();
	FILE* file = fopen(ADMIN_LIST_FILE, "r");

	if (!file) {
		string text = string("[Radio] Failed to open: ") + ADMIN_LIST_FILE + "\n";
		println(text);
		logln(text);
		return;
	}

	string line;
	while (cgetline(file, line)) {
		if (line.empty()) {
			continue;
		}

		// strip comments
		int endPos = line.find_first_of(" \t#/\n");
		string steamId = trimSpaces(line.substr(0, endPos));

		if (steamId.length() < 1) {
			continue;
		}

		int adminLevel = ADMIN_YES;

		if (steamId[0] == '*') {
			adminLevel = ADMIN_OWNER;
			steamId = steamId.substr(1);
		}

		g_admins[steamId] = adminLevel;
	}

	println(UTIL_VarArgs("[Radio] Loaded %d admin(s) from file", g_admins.size()));

	fclose(file);
}

int AdminLevel(edict_t* plr) {
	string steamId = (*g_engfuncs.pfnGetPlayerAuthId)(plr);

	if (!IS_DEDICATED_SERVER()) {
		if (ENTINDEX(plr) == 1) {
			return ADMIN_OWNER; // listen server owner is always the first player to join (I hope)
		}
	}

	if (g_admins.find(steamId) != g_admins.end()) {
		return g_admins[steamId];
	}
	
	return ADMIN_NO;
}

char* UTIL_VarArgs(char* format, ...)
{
	va_list		argptr;
	static char		string[1024];

	va_start(argptr, format);
	vsprintf(string, format, argptr);
	va_end(argptr);

	return string;
}

CommandArgs::CommandArgs() {
	
}

void CommandArgs::loadArgs() {
	isConsoleCmd = toLowerCase(CMD_ARGV(0)) != "say";

	string argStr = CMD_ARGC() > 1 ? CMD_ARGS() : "";

	if (isConsoleCmd) {
		argStr = CMD_ARGV(0) + string(" ") + argStr;
	}

	if (!isConsoleCmd && argStr.length() > 2 && argStr[0] == '\"' && argStr[argStr.length() - 1] == '\"') {
		argStr = argStr.substr(1, argStr.length() - 2); // strip surrounding quotes
	}

	while (!argStr.empty()) {
		// strip spaces
		argStr = trimSpaces(argStr);


		if (argStr[0] == '\"') { // quoted argument (include the spaces between quotes)
			argStr = argStr.substr(1);
			int endQuote = argStr.find("\"");

			if (endQuote == -1) {
				args.push_back(argStr);
				break;
			}

			args.push_back(argStr.substr(0, endQuote));
			argStr = argStr.substr(endQuote + 1);
		}
		else {
			// normal argument, separate by space
			int nextSpace = argStr.find(" ");

			if (nextSpace == -1) {
				args.push_back(argStr);
				break;
			}

			args.push_back(argStr.substr(0, nextSpace));
			argStr = argStr.substr(nextSpace + 1);
		}
	}
}

string CommandArgs::ArgV(int idx) {
	if (idx >= 0 && idx < args.size()) {
		return args[idx];
	}

	return "";
}

int CommandArgs::ArgC() {
	return args.size();
}

string CommandArgs::getFullCommand() {
	string str = ArgV(0);

	for (int i = 1; i < args.size(); i++) {
		str += " " + args[i];
	}

	return str;
}

using namespace std::chrono;

uint64_t getEpochMillis() {
	return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

double TimeDifference(uint64_t start, uint64_t end) {
	if (end > start) {
		return (end - start) / 1000.0;
	}
	else {
		return -((start - end) / 1000.0);
	}
}