#pragma once
#include "meta_utils.h"

#define MSG_CdAudio 80
#define MSG_StartSound 107

#define SND_VOLUME 1
#define SND_PITCH 2
#define SND_ATTENUATION 4
#define SND_ORIGIN 8
#define SND_ENT 16
#define SND_STOP 32
#define SND_CHANGE_VOL 64
#define SND_CHANGE_PITCH 128
#define SND_SENTENCE 256
#define SND_REFRESH 512
#define SND_FORCE_SINGLE 1024
#define SND_FORCE_LOOP 2048
#define SND_LINEAR 4096
#define SND_SKIP_ORIGIN_USE_ENT 8192
#define SND_IDK 16384 // this is set by ambient_music but idk what it does
#define SND_OFFSET 32768

#define CHAN_MUSIC 7

#define FL_UNLOOPED_CYCLIC 32

enum message_arg_types {
	MARG_NONE,
	MARG_ANGLE,
	MARG_BYTE,
	MARG_CHAR,
	MARG_COORD,
	MARG_ENT,
	MARG_LONG,
	MARG_SHORT,
	MARG_STRING
};

struct MessageArg {
	int argType = MARG_NONE;
	int ival = 0;
	float fval = 0;
	const char* sval = "";

	MessageArg(int argType, int ival);
	MessageArg(int argType, float ival);
	MessageArg(int argType, const char* sval);
	void writeToCurrentMessage();
	const char* getString();
};

struct NetMessage {
	vector<MessageArg> args;
	int msg_type = -1;
	int msg_dest;
	float pOrigin[3];
	bool hasOrigin;
	edict_t* ed;

	NetMessage() {}
	void send(int msg_dest, edict_t* ed);
	void send();
	void clear();
	void print();
};

enum sound_msg_type {
	MSND_START, // start a new sound
	MSND_STOP, // stop a currently playing sound
	MSND_UPDATE // update a currently playing sound (does not start a stopped sound)
};

struct StartSoundMsg {
	string sample = "";
	int soundIdx;
	int channel = 0;
	float volume = 1.0f;
	float attenuation = 1.0f;
	int pitch = 100;
	float offset = 0;
	int entindex = -1;
	float x, y, z;
	int flags;

	// original network message args
	int msg_dest;
	edict_t* ed;

	StartSoundMsg() {}
	StartSoundMsg(const StartSoundMsg& other);
	StartSoundMsg(const NetMessage& msg);
	void print();
	void simplePrint();
	bool isMusic();
	int getMsgType();
	void send(edict_t* target);
	char* getDesc();
	bool isBuggedCyclicSound();
	bool isAmbientGeneric();
};

struct LoopingSound {
	NetMessage msg;
	StartSoundMsg info;
	uint64_t sendTime;
	bool isPlaying = true;

	LoopingSound(const NetMessage& msg);
	void pause(edict_t* target);
	void resume(edict_t* target);

	// returns true if this sound would be stopped/replaced by the given sound message 
	bool wouldBeStoppedBy(StartSoundMsg& msg);
};

void MessageBegin(int msg_dest, int msg_type, const float* pOrigin, edict_t* ed);

void MessageEnd();
void MessageEnd_post();
void WriteAngle(float angle);
void WriteByte(int b);
void WriteChar(int c);
void WriteCoord(float coord);
void WriteEntity(int ent);
void WriteLong(int val);
void WriteShort(int val);
void WriteString(const char* s);