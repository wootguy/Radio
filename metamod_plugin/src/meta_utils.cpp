#include "meta_utils.h"

Scheduler g_scheduler;

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

cvar_t* RegisterCVar(char* name, char* defaultValue, int flags, int value) {
	
	if (g_cvar_count >= MAX_CVARS) {
		println("Failed to add cvar '%s'. Increase MAX_CVARS and recompile.", name);
		return NULL;
	}

	g_cvar_data[g_cvar_count].name = name;
	g_cvar_data[g_cvar_count].string = defaultValue;
	g_cvar_data[g_cvar_count].flags = flags | FCVAR_EXTDLL;
	g_cvar_data[g_cvar_count].value = value;
	g_cvar_data[g_cvar_count].next = NULL;

	CVAR_REGISTER(&g_cvar_data[g_cvar_count]);

	g_cvar_count++;

	return CVAR_GET_POINTER(name);
}

//
// Funcs copied from HLSDK
//

void UTIL_ClientPrintAll(int msg_dest, const char* msg_name, const char* param1, const char* param2, const char* param3, const char* param4)
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

void ClientPrint(entvars_t* client, int msg_dest, const char* msg_name, const char* param1, const char* param2, const char* param3, const char* param4)
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

static unsigned short FixedUnsigned16(float value, float scale)
{
	int output;

	output = value * scale;
	if (output < 0)
		output = 0;
	if (output > 0xFFFF)
		output = 0xFFFF;

	return (unsigned short)output;
}

static short FixedSigned16(float value, float scale)
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
void UTIL_HudMessage(edict_t* pEntity, const hudtextparms_t& textparms, const char* pMessage)
{
	int dest = pEntity ? MSG_ONE : MSG_ALL;

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

void UTIL_HudMessageAll(const hudtextparms_t& textparms, const char* pMessage)
{
	UTIL_HudMessage(NULL, textparms, pMessage);
}