#pragma once

#include "meta_init.h"
#include <string>
#include <vector>
#include <map>
#include "Scheduler.h"

using namespace std; // ohhh yesss

#define MAX_PLAYERS 32

#define MSG_TextMsg 75

// get a player index as a bitfield index
#define PLAYER_BIT(edt) (1 << (ENTINDEX(edt) % 32))

extern Scheduler g_Scheduler;

#define print(fmt,...) {ALERT(at_console, (char*)string(fmt).c_str(), __VA_ARGS__);}
#define println(fmt,...) {ALERT(at_console, (char*)string(fmt).c_str(), __VA_ARGS__); ALERT(at_console, "\n"); }

#define log(fmt, ...) {ALERT(at_logged, (char*)string(fmt).c_str(), __VA_ARGS__);}
#define logln(fmt,...) {ALERT(at_logged, (char*)string(fmt).c_str(), __VA_ARGS__); ALERT(at_logged, "\n"); }

enum AdminLevel_t {
	ADMIN_INIT = -1,
	ADMIN_NO,
	ADMIN_YES,
	ADMIN_OWNER
};

struct CommandArgs {
	vector<string> args;
	bool isConsoleCmd;
	
	// gets current globally defined args
	CommandArgs();

	// returns empty string if idx is out of bounds
	string ArgV(int idx);

	// return number of args
	int ArgC();

	// return entire command string
	string getFullCommand();
};

string toLowerCase(string str);

cvar_t* RegisterCVar(char* name, char* strDefaultValue, int intDefaultValue, int flags);

void HudMessageAll(const hudtextparms_t& textparms, const char* pMessage);
void HudMessage(edict_t* pEntity, const hudtextparms_t& textparms, const char* pMessage);
void ClientPrintAll(int msg_dest, const char* msg_name, const char* param1 = NULL, const char* param2 = NULL, const char* param3 = NULL, const char* param4 = NULL);
void ClientPrint(edict_t* client, int msg_dest, const char* msg_name, const char* param1 = NULL, const char* param2 = NULL, const char* param3 = NULL, const char* param4 = NULL);
void LoadAdminList(); // call on each map change, so AdminLevel can work
int AdminLevel(edict_t* player);
char* UTIL_VarArgs(char* format, ...);
uint64_t getEpochMilliszz();
double TimeDifferencezz(uint64_t start, uint64_t end);
