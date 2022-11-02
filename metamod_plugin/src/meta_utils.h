#pragma once

#include "meta_init.h"
#include <string>
#include <vector>
#include <map>
#include "Scheduler.h"
#include "ThreadSafeQueue.h"
#include <thread>
#include <algorithm>

using namespace std; // ohhh yesss

#define MAX_PLAYERS 32

#define MSG_TextMsg 75

// get a player index as a bitfield index
#define PLAYER_BIT(edt) (1 << (ENTINDEX(edt) % 32))

extern Scheduler g_Scheduler;
extern thread::id g_main_thread_id;
extern ThreadSafeQueue<string> g_thread_prints;
extern ThreadSafeQueue<string> g_thread_logs;

//#define print(fmt,...) {ALERT(at_console, (char*)string(fmt).c_str(), ##__VA_ARGS__);}

// thread safe console printing
#define println(fmt,...) { \
	std::thread::id thisId = std::this_thread::get_id(); \
	if (thisId == g_main_thread_id) { \
		ALERT(at_console, (char*)(string(fmt) + "\n").c_str(), ##__VA_ARGS__ ); \
	} \
	else { \
		g_thread_prints.enqueue(UTIL_VarArgs((char*)string(fmt).c_str(), ##__VA_ARGS__ )); \
	} \
}

//#define log(fmt, ...) {ALERT(at_logged, (char*)string(fmt).c_str(), ##__VA_ARGS__);}

#define logln(fmt,...) { \
	std::thread::id thisId = std::this_thread::get_id(); \
	if (thisId == g_main_thread_id) { \
		ALERT(at_logged, (char*)(string(fmt) + "\n").c_str(), ##__VA_ARGS__ ); \
	} \
	else { \
		g_thread_logs.enqueue(UTIL_VarArgs((char*)string(fmt).c_str(), ##__VA_ARGS__ )); \
	} \
}

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

void HudMessageAll(const hudtextparms_t& textparms, const char* pMessage, int dest = -1);
void HudMessage(edict_t* pEntity, const hudtextparms_t& textparms, const char* pMessage, int dest = -1); 
void ClientPrintAll(int msg_dest, const char* msg_name, const char* param1 = NULL, const char* param2 = NULL, const char* param3 = NULL, const char* param4 = NULL);
void ClientPrint(edict_t* client, int msg_dest, const char* msg_name, const char* param1 = NULL, const char* param2 = NULL, const char* param3 = NULL, const char* param4 = NULL);
void LoadAdminList(); // call on each map change, so AdminLevel can work
int AdminLevel(edict_t* player);
char* UTIL_VarArgs(char* format, ...);
uint64_t getEpochMillis();
double TimeDifference(uint64_t start, uint64_t end);
