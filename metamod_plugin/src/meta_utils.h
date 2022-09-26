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

extern Scheduler g_scheduler;

#define print(...) {ALERT(at_console, __VA_ARGS__);}
#define println(...) {ALERT(at_console, __VA_ARGS__); ALERT(at_console, "\n"); }

string toLowerCase(string str);

cvar_t* RegisterCVar(char* name, char* defaultValue, int flags, int value);

void UTIL_HudMessage(edict_t* pEntity, const hudtextparms_t& textparms, const char* pMessage);
