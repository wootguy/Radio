#include "message_overrides.h"
#include "TextMenu.h"
#include "radio_utils.h"

bool g_suppress_current_message = false;
bool g_log_next_message = false;

#define MAX_CD_AUDIO_TRACKS 27

const char* g_audio_tracks[MAX_CD_AUDIO_TRACKS] = {
	"media/Half-Life01.mp3",
	"media/Half-Life02.mp3",
	"media/Half-Life03.mp3",
	"media/Half-Life04.mp3",
	"media/Half-Life05.mp3",
	"media/Half-Life06.mp3",
	"media/Half-Life07.mp3",
	"media/Half-Life08.mp3",
	"media/Half-Life09.mp3",
	"media/Half-Life10.mp3",
	"media/Half-Life11.mp3",
	"media/Half-Life12.mp3",
	"media/Half-Life13.mp3",
	"media/Half-Life14.mp3",
	"media/Half-Life15.mp3",
	"media/Half-Life16.mp3",
	"media/Half-Life17.mp3",
	"media/Half-Life18.mp3",
	"media/Half-Life19.mp3",
	"media/Half-Life20.mp3",
	"media/Half-Life21.mp3",
	"media/Half-Life22.mp3",
	"media/Half-Life23.mp3",
	"media/Half-Life24.mp3",
	"media/Half-Life25.mp3",
	"media/Half-Life26.mp3",
	"media/Half-Life27.mp3"
};

// stores the last network message that was suppressed
NetMessage g_suppressed_message;

MessageArg::MessageArg(int argType, int ival) {
	this->argType = argType;
	this->ival = ival;
}

MessageArg::MessageArg(int argType, float fval) {
	this->argType = argType;
	this->fval = fval;
}

MessageArg::MessageArg(int argType, const char* sval) {
	this->argType = argType;
	this->sval = sval;
}

void MessageArg::writeToCurrentMessage() {
	switch (argType) {
	case MARG_NONE:
		break;
	case MARG_ANGLE:
		WRITE_ANGLE(fval);
		break;
	case MARG_BYTE:
		WRITE_BYTE(ival);
		break;
	case MARG_CHAR:
		WRITE_CHAR(ival);
		break;
	case MARG_COORD:
		WRITE_COORD(fval);
		break;
	case MARG_ENT:
		WRITE_ENTITY(ival);
		break;
	case MARG_LONG:
		WRITE_LONG(ival);
		break;
	case MARG_SHORT:
		WRITE_SHORT(ival);
		break;
	case MARG_STRING:
		WRITE_STRING(sval);
		break;
	default:
		break;
	}
}

const char* MessageArg::getString() {
	switch (argType) {
	case MARG_ANGLE:  return UTIL_VarArgs("ANGLE  : %f", fval);
	case MARG_BYTE:   return UTIL_VarArgs("BYTE   : %d", ival);
	case MARG_CHAR:   return UTIL_VarArgs("CHAR   : %d", ival);
	case MARG_COORD:  return UTIL_VarArgs("COORD  : %f", fval);
	case MARG_ENT:    return UTIL_VarArgs("ENTITY : %d", ival);
	case MARG_LONG:   return UTIL_VarArgs("LONG   : %d", ival);
	case MARG_SHORT:  return UTIL_VarArgs("SHORT  : %d", ival);
	case MARG_STRING: return UTIL_VarArgs("STRING: %s", sval);
	default:
		return "NONE";
	}
}

void NetMessage::send(int msg_dest, edict_t* ed) {
	if (msg_type == -1) {
		println("Can't send unintialized net message");
		return;
	}

	const float* origin = hasOrigin ? pOrigin : NULL;

	MESSAGE_BEGIN(msg_dest, msg_type, origin, ed);

	for (int i = 0; i < args.size(); i++) {
		args[i].writeToCurrentMessage();
	}

	MESSAGE_END();
}

void NetMessage::send() {
	send(msg_dest, ed);
}

void NetMessage::clear() {
	args.clear();
	msg_type = -1;
}

const char* msgDestStr(int msg_dest) {
	const char* sdst = "";
	switch (msg_dest) {
	case MSG_BROADCAST:
		sdst = "MSG_BROADCAST";
		break;
	case MSG_ONE:
		sdst = "MSG_ONE";
		break;
	case MSG_ALL:
		sdst = "MSG_ALL";
		break;
	case MSG_INIT:
		sdst = "MSG_INIT";
		break;
	case MSG_PVS:
		sdst = "MSG_PVS";
		break;
	case MSG_PAS:
		sdst = "MSG_PAS";
		break;
	case MSG_PVS_R:
		sdst = "MSG_PVS_R";
		break;
	case MSG_PAS_R:
		sdst = "MSG_PAS_R";
		break;
	case MSG_ONE_UNRELIABLE:
		sdst = "MSG_ONE_UNRELIABLE";
		break;
	case MSG_SPEC:
		sdst = "MSG_SPEC";
		break;
	default:
		sdst = UTIL_VarArgs("%d (unkown)", msg_dest);
		break;
	}

	return sdst;
}

void NetMessage::print() {
	char* origin = pOrigin ? UTIL_VarArgs("Vector(%f %f %f)", pOrigin[0], pOrigin[1], pOrigin[2]) : "NULL";
	const char* sed = ed ? STRING(ed->v.classname) : "NULL";

	println("BEGIN(%s, %d, %s, %s)", msgDestStr(msg_dest), msg_type, origin, sed);
	for (int i = 0; i < args.size(); i++) {
		println("    %s", args[i].getString());
	}
	println("END");
}

StartSoundMsg::StartSoundMsg(const StartSoundMsg& other) {
	this->sample = other.sample;
	this->soundIdx = other.soundIdx;
	this->channel = other.channel;
	this->volume = other.volume;
	this->attenuation = other.attenuation;
	this->pitch = other.pitch;
	this->offset = other.offset;
	this->entindex = other.entindex;
	this->x = other.x;
	this->y = other.y;
	this->z = other.z;
	this->flags = other.flags;
	this->msg_dest = other.msg_dest;
	this->ed = other.ed;
}

StartSoundMsg::StartSoundMsg(const NetMessage& msg) {
	flags = msg.args[0].ival;
	int argIdx = 1;

	if (flags & SND_ENT) {
		entindex = msg.args[argIdx++].ival;
	}
	if (flags & SND_VOLUME) {
		volume = msg.args[argIdx++].ival / 255.0f;
	}
	if (flags & SND_PITCH) {
		pitch = msg.args[argIdx++].ival;
	}
	if (flags & SND_ATTENUATION) {
		attenuation = msg.args[argIdx++].ival / 64.0f;
	}
	if (flags & SND_ORIGIN) {
		x = msg.args[argIdx++].fval;
		y = msg.args[argIdx++].fval;
		z = msg.args[argIdx++].fval;
	}
	if (flags & SND_OFFSET) {
		// sven must have some sort of WRITE_FLOAT macro which actually writes bytes
		// wonder why WRITE_COORD wasn't good enough?
		uint8_t fbytes[4];
		fbytes[0] = msg.args[argIdx++].ival;
		fbytes[1] = msg.args[argIdx++].ival;
		fbytes[2] = msg.args[argIdx++].ival;
		fbytes[3] = msg.args[argIdx++].ival;
		offset = *(float*)fbytes;
	}

	channel = msg.args[argIdx++].ival;
	soundIdx = msg.args[argIdx++].ival;
	sample = g_index_sounds[soundIdx];

	msg_dest = msg.msg_dest;
	ed = msg.ed;
}

void StartSoundMsg::send(edict_t* target) {
	MESSAGE_BEGIN(MSG_ONE, MSG_StartSound, NULL, target);
	WRITE_SHORT(flags);

	if (flags & SND_ENT) {
		WRITE_SHORT(entindex);
	}
	if (flags & SND_VOLUME) {
		WRITE_BYTE(clamp(int(volume * 255), 0, 255));
	}
	if (flags & SND_PITCH) {
		WRITE_BYTE(pitch);
	}
	if (flags & SND_ATTENUATION) {
		WRITE_BYTE(clamp(int(attenuation * 64), 0, 255));
	}
	if (flags & SND_ORIGIN) {
		WRITE_COORD(x);
		WRITE_COORD(y);
		WRITE_COORD(z);
	}
	if (flags & SND_OFFSET) {
		uint8_t* fbytes = (uint8_t*)&offset;
		WRITE_BYTE(fbytes[0]);
		WRITE_BYTE(fbytes[1]);
		WRITE_BYTE(fbytes[2]);
		WRITE_BYTE(fbytes[3]);
	}

	WRITE_BYTE(channel);
	WRITE_SHORT(soundIdx);

	MESSAGE_END();
}

const char* getChannelName(int channel) {
	const char* schan = "";

	switch (channel) {
	case CHAN_AUTO:
		schan = "CHAN_AUTO";
		break;
	case CHAN_WEAPON:
		schan = "CHAN_WEAPON";
		break;
	case CHAN_VOICE:
		schan = "CHAN_VOICE";
		break;
	case CHAN_BODY:
		schan = "CHAN_BODY";
		break;
	case CHAN_STREAM:
		schan = "CHAN_STREAM";
		break;
	case CHAN_STATIC:
		schan = "CHAN_STATIC";
		break;
	case CHAN_MUSIC:
		schan = "CHAN_MUSIC";
		break;
	}

	return schan;
}

void StartSoundMsg::print() {
	string flagString;

	println("BEGIN StartSound message (%s):", msgDestStr(msg_dest));

	if (flags & SND_VOLUME) flagString += " SND_VOLUME";
	if (flags & SND_PITCH) flagString += " SND_CHANGE_PITCH";
	if (flags & SND_ATTENUATION) flagString += " SND_ATTENUATION";
	if (flags & SND_ORIGIN) flagString += " SND_ORIGIN";
	if (flags & SND_ENT) flagString += " SND_ENT";
	if (flags & SND_STOP) flagString += " SND_STOP";
	if (flags & SND_CHANGE_VOL) flagString += " SND_CHANGE_VOL";
	if (flags & SND_CHANGE_PITCH) flagString += " SND_CHANGE_PITCH";
	if (flags & SND_SENTENCE) flagString += " SND_SENTENCE";
	if (flags & SND_REFRESH) flagString += " SND_REFRESH";
	if (flags & SND_FORCE_SINGLE) flagString += " SND_FORCE_SINGLE";
	if (flags & SND_FORCE_LOOP) flagString += " SND_FORCE_LOOP";
	if (flags & SND_LINEAR) flagString += " SND_LINEAR";
	if (flags & SND_SKIP_ORIGIN_USE_ENT) flagString += " SND_SKIP_ORIGIN_USE_ENT";
	if (flags & SND_IDK) flagString += " SND_IDK";
	if (flags & SND_OFFSET) flagString += " SND_OFFSET";

	println("    Flags :%s", flagString.c_str());
	if (flags & SND_ENT) {
		string entString = "NULL";
		if (entindex != -1)
			entString = UTIL_VarArgs("%s (%s)", STRING(INDEXENT(entindex)->v.targetname), 
				STRING(INDEXENT(entindex)->v.classname));
		println("    Entity: %s", entString.c_str());
	}
	if (flags & SND_VOLUME) {
		println("    Volume: %f", volume);
	}
	if (flags & SND_PITCH) {
		println("    Pitch : %d", pitch);
	}
	if (flags & SND_ATTENUATION) {
		println("    Attn  : %f", attenuation);
	}
	if (flags & SND_ORIGIN) {
		println("    Origin: %.f %.f %.1f", x, y, z);
	}
	if (flags & SND_OFFSET) {
		println("    Offset: %f", offset);
	}
	
	println("    Channl: %s", getChannelName(channel));
	println("    Sound : %s", sample.c_str());
	println("END");
}

char* StartSoundMsg::getDesc() {
	static char buff[256];

	string name = sample;
	int lastSlash = sample.find_last_of("/");
	if (lastSlash != -1) {
		name = name.substr(lastSlash+1);
	}

	char* temp = UTIL_VarArgs("ent_%d[%s]: %s", (int)entindex, getChannelName(channel), name.c_str());
	strncpy(buff, temp, 256);

	return buff;
}

void StartSoundMsg::simplePrint() {
	int msgType = getMsgType();

	if (msgType == MSND_STOP) {
		println("Stop: ent_%d[%d]: %s", entindex, channel, sample.c_str());
	}
	else if (msgType == MSND_UPDATE) {
		println("Refresh: ent_%d[%d]: %s", entindex, channel, sample.c_str());
	}
	else {
		println("Start: ent_%d[%d]: %s", entindex, channel, sample.c_str());
	}
}

bool StartSoundMsg::isMusic() {
	if (flags & SND_IDK) { // ambient_music
		return true;
	}
	/*
	if (flags & SND_FORCE_LOOP) {
		return true; // looping ambient_generic
	}
	*/
	if ((flags & SND_STOP)) {
		return channel != CHAN_AUTO; // could be for music. Needed to know which sounds should be restarted
	}
	if (attenuation == 0.0f) {
		return true; // global sound
	}

	int eidx = ed ? ENTINDEX(ed) : -1;
	if (eidx > 0 && eidx <= gpGlobals->maxClients) {
		// sound attached to a player, with a message only heard by that player
		// maps can use this for music to keep sound balanced in both ears
		return true; 
	}

	return false;
}

bool StartSoundMsg::isBuggedCyclicSound() {
	edict_t* emitter = flags & SND_ENT ? INDEXENT(entindex) : NULL;

	return emitter
		&& (emitter->v.spawnflags & FL_UNLOOPED_CYCLIC)
		&& strcmp(STRING(emitter->v.classname), "ambient_generic") == 0;
}

int StartSoundMsg::getMsgType() {
	if (flags & SND_STOP) {
		return MSND_STOP;
	}
	else if (flags & (SND_CHANGE_VOL | SND_CHANGE_PITCH | SND_REFRESH)) {
		return MSND_UPDATE;
	}
	return MSND_START;
}

LoopingSound::LoopingSound(const NetMessage& msg) {
	this->msg = msg;
	this->info = StartSoundMsg(msg);
	sendTime = getEpochMillis();
}

void LoopingSound::pause(edict_t* target) {
	//ClientPrint(target, HUD_PRINTNOTIFY, "[Radio] Paused map music: %s\n", info.sample.c_str());

	StartSoundMsg pauseSnd = StartSoundMsg(info);
	pauseSnd.flags = info.flags | SND_VOLUME | SND_CHANGE_VOL | SND_REFRESH;
	pauseSnd.volume = 0.0f; // only change the volume so that it doesn't need to restart on resume

	if ((info.flags & SND_FORCE_LOOP) == 0) {
		pauseSnd.flags = (info.flags & (SND_ENT | SND_ORIGIN)) | SND_STOP; // volume can't be adjusted after sound starts. Just stop it.
	}

	//println("HERE DAT PAUSE MSG");
	pauseSnd.print();

	if (pauseSnd.channel == CHAN_AUTO) {
		// can't know which channel was chosen to play on, so try to stop it on all channels
		for (int i = 1; i <= 7; i++) {
			pauseSnd.channel = i;
			pauseSnd.send(target);
		}
	}
	else {
		pauseSnd.send(target);
	}
	
	isPlaying = false;
}

void LoopingSound::resume(edict_t* target) {
	// ambient music offset increment
	uint64_t now = getEpochMillis();
	info.offset += TimeDifference(sendTime, now);
	sendTime = now;

	//ClientPrint(target, HUD_PRINTNOTIFY, "[Radio] Resumed map music: %s\n", info.sample.c_str());

	StartSoundMsg resumeSnd = StartSoundMsg(info);
	resumeSnd.flags = info.flags | SND_VOLUME | SND_CHANGE_VOL | SND_REFRESH;

	if ((info.flags & SND_FORCE_LOOP) == 0) {
		// volume can't be adjusted after sound starts. Must be restarted.
		resumeSnd.flags = info.flags & ~(SND_CHANGE_VOL | SND_REFRESH | SND_CHANGE_PITCH);
		resumeSnd.flags |= SND_OFFSET;
	}

	//println("HERE DAT RESUME MSG");
	resumeSnd.print();

	resumeSnd.send(target);
	isPlaying = true;
}

bool LoopingSound::wouldBeStoppedBy(StartSoundMsg& msg) {
	return info.channel == msg.channel && info.entindex == msg.entindex && info.sample == msg.sample;
}

void handleStartSoundMessage(edict_t* plr, NetMessage& msg, StartSoundMsg& startSnd) {
	if (!isValidPlayer(plr)) {
		return;
	}

	PlayerState& state = getPlayerState(plr);
	
	int msgType = startSnd.getMsgType();

	if (msgType == MSND_START || msgType == MSND_UPDATE) {
		int oldCount = state.activeMapMusic.size();
		const char* mtype = msgType == MSND_START ? "START" : "UPDATE";

		if (msgType == MSND_START) {
			// don't delete on updates because that messes up resume offset

			for (int i = 0; i < state.activeMapMusic.size(); i++) {
				if (state.activeMapMusic[i].wouldBeStoppedBy(startSnd)) {
					state.activeMapMusic.erase(state.activeMapMusic.begin() + i);
					break;
				}
			}

			state.activeMapMusic.push_back(LoopingSound(msg));
		}

		if (state.isRadioMusicPlaying()) {
			if (msgType == MSND_START)
				ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] Muted map music: %s\n", startSnd.sample.c_str());
		}
		else {
			msg.send(MSG_ONE, plr);
			//ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] NOT Suppressing map music (all): %s\n", startSnd.sample.c_str());
		}

		if (state.activeMapMusic.size() > oldCount) {
			//ClientPrint(plr, HUD_PRINTTALK, UTIL_VarArgs("%s message %.2f added %s\n", mtype, gpGlobals->time, startSnd.getDesc()));
		}
		else if (state.activeMapMusic.size() == oldCount) {
			//ClientPrint(plr, HUD_PRINTTALK, UTIL_VarArgs("%s message %.2f replaced %s\n", mtype, gpGlobals->time, startSnd.getDesc()));
		}
		else {
			//ClientPrint(plr, HUD_PRINTTALK, UTIL_VarArgs("%s message %.2f DID SOMETHING IMPOSSIBLE to %s\n", mtype, gpGlobals->time, startSnd.getDesc()));
		}
	}
	else if (msgType == MSND_STOP) {
		bool foundAnyStop = false;
		for (int i = 0; i < state.activeMapMusic.size(); i++) {
			if (state.activeMapMusic[i].wouldBeStoppedBy(startSnd)) {
				state.activeMapMusic.erase(state.activeMapMusic.begin() + i);
				foundAnyStop = true;
				//ClientPrint(plr, HUD_PRINTTALK, UTIL_VarArgs("STOP message %.2f stopped %s\n", gpGlobals->time, startSnd.getDesc()));
				break;
			}
		}

		if (!foundAnyStop) {
			//ClientPrint(plr, HUD_PRINTTALK, UTIL_VarArgs("STOP message %.2f did not stop any music\n", gpGlobals->time));
		}

		msg.send();
	}
	else {
		println("Invalid StartSnd message type %d", msgType);
	}
}

void handleCdAudioMessage(edict_t* plr, NetMessage& msg, string sound) {
	if (!isValidPlayer(plr)) {
		return;
	}
	PlayerState& state = getPlayerState(plr);

	if (state.isRadioMusicPlaying()) {
		ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] Muted map music: %s\n", sound.c_str());
	}
	else {
		msg.send(MSG_ONE, plr);
		//ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] NOT Suppressing map music: %s\n", sound.c_str());
	}
}

void hookAudioMessage(NetMessage& msg) {
	bool isMusic = false;

	if (msg.msg_type == MSG_CdAudio) {
		int idx = msg.args[0].ival;

		string sound = "???";
		if (idx >= 0 || idx < MAX_CD_AUDIO_TRACKS) {
			sound = g_audio_tracks[idx];
		}

		if (msg.msg_dest == MSG_ALL) {
			for (int i = 1; i <= gpGlobals->maxClients; i++) {
				handleCdAudioMessage(INDEXENT(i), msg, sound);
			}
		}
		else if (msg.msg_dest == MSG_ONE) {
			handleCdAudioMessage(msg.ed, msg, sound);
		}

		return;
	}

	if (msg.msg_type != MSG_StartSound) {
		msg.send();
		return;
	}

	StartSoundMsg startSnd = StartSoundMsg(msg);

	if (!startSnd.isMusic()) {
		msg.send();
		//println("Ignoring non-music message");
		return;
	}
	
	startSnd.print();
	//msg.print();

	if (startSnd.isBuggedCyclicSound() && (startSnd.flags & SND_STOP)) {
		// cyclic ambient_generics send a stop sound message right before the play sound message.
		// This causes the sounds not to play at all, even if you were to send a duplicate start
		// message here. Just ignore stop messages because you can't turn off a cylic sound
		// anyway via OFF triggers so there's no point in sending stop messages for it. Triggering
		// it again restarts the sound on the same channel. There's really no need to stop first.
		println("Dropped cyclic stop sound message");
		return;
	}

	if (msg.msg_dest == MSG_BROADCAST || msg.msg_dest == MSG_ALL) {
		for (int i = 1; i <= gpGlobals->maxClients; i++) {
			handleStartSoundMessage(INDEXENT(i), msg, startSnd);
		}
	}
	else if (msg.msg_dest == MSG_ONE || msg.msg_dest == MSG_ONE_UNRELIABLE) {
		handleStartSoundMessage(msg.ed, msg, startSnd);
	}
	else {
		println("[Radio] Unexpected StartSound dest: %d", msg.msg_dest);
	}
}

// Important: MessageBegin is only hooked when called from the game.
// MessageBegin calls in this plugin will bypasses the hook
void MessageBegin(int msg_dest, int msg_type, const float* pOrigin, edict_t* ed) {
	TextMenuMessageBeginHook(msg_dest, msg_type, pOrigin, ed);
	/*
	g_log_next_message = false;
	if (msg_type == MSG_StartSound) {
		g_suppressed_message.clear();
		g_suppressed_message.msg_type = msg_type;
		g_suppressed_message.pOrigin = pOrigin;
		g_suppressed_message.msg_dest = msg_dest;
		g_suppressed_message.ed = ed;
		g_log_next_message = true;
	}
	*/
	
	if (msg_type == MSG_StartSound || msg_type == MSG_CdAudio) {
		// wait until the args are checked before sending this message.
		// music shouldn't be sent to radio listeners.
		g_suppress_current_message = true;
		g_suppressed_message.clear();
		g_suppressed_message.msg_type = msg_type;
		g_suppressed_message.hasOrigin = false;
		if (pOrigin) {
			g_suppressed_message.hasOrigin = true;
			g_suppressed_message.pOrigin[0] = pOrigin[0];
			g_suppressed_message.pOrigin[1] = pOrigin[1];
			g_suppressed_message.pOrigin[2] = pOrigin[2];
		}
		g_suppressed_message.msg_dest = msg_dest;
		g_suppressed_message.ed = ed;
		RETURN_META(MRES_SUPERCEDE);
	}

	RETURN_META(MRES_IGNORED);
}

void MessageEnd() {
	if (g_suppress_current_message) {
		RETURN_META(MRES_SUPERCEDE);
	}
	RETURN_META(MRES_IGNORED);
}

void MessageEnd_post() {
	if (g_log_next_message) {
		g_suppressed_message.print();
	}
	if (g_suppress_current_message) {
		g_suppress_current_message = false;
		hookAudioMessage(g_suppressed_message);
	}
	RETURN_META(MRES_IGNORED);
}

void WriteAngle(float angle) {
	if (g_log_next_message || g_suppress_current_message) {
		g_suppressed_message.args.push_back(MessageArg(MARG_ANGLE, angle));
	}
	if (g_suppress_current_message) {
		RETURN_META(MRES_SUPERCEDE);
	}
	RETURN_META(MRES_IGNORED);
}

void WriteByte(int b) {
	if (g_log_next_message || g_suppress_current_message) {
		g_suppressed_message.args.push_back(MessageArg(MARG_BYTE, b));
	}
	if (g_suppress_current_message) {
		RETURN_META(MRES_SUPERCEDE);
	}
	RETURN_META(MRES_IGNORED);
}

void WriteChar(int c) {
	if (g_log_next_message || g_suppress_current_message) {
		g_suppressed_message.args.push_back(MessageArg(MARG_CHAR, c));
	}
	if (g_suppress_current_message) {
		RETURN_META(MRES_SUPERCEDE);
	}
	RETURN_META(MRES_IGNORED);
}

void WriteCoord(float coord) {
	if (g_log_next_message || g_suppress_current_message) {
		g_suppressed_message.args.push_back(MessageArg(MARG_COORD, coord));
	}
	if (g_suppress_current_message) {
		RETURN_META(MRES_SUPERCEDE);
	}
	RETURN_META(MRES_IGNORED);
}

void WriteEntity(int ent) {
	if (g_log_next_message || g_suppress_current_message) {
		g_suppressed_message.args.push_back(MessageArg(MARG_ENT, ent));
	}
	if (g_suppress_current_message) {
		RETURN_META(MRES_SUPERCEDE);
	}
	RETURN_META(MRES_IGNORED);
}

void WriteLong(int val) {
	if (g_log_next_message || g_suppress_current_message) {
		g_suppressed_message.args.push_back(MessageArg(MARG_LONG, val));
	}
	if (g_suppress_current_message) {
		RETURN_META(MRES_SUPERCEDE);
	}
	RETURN_META(MRES_IGNORED);
}

void WriteShort(int val) {
	if (g_log_next_message || g_suppress_current_message) {
		g_suppressed_message.args.push_back(MessageArg(MARG_SHORT, val));
	}
	if (g_suppress_current_message) {
		RETURN_META(MRES_SUPERCEDE);
	}
	RETURN_META(MRES_IGNORED);
}

void WriteString(const char* s) {
	if (g_log_next_message || g_suppress_current_message) {
		g_suppressed_message.args.push_back(MessageArg(MARG_STRING, s));
	}
	if (g_suppress_current_message) {
		RETURN_META(MRES_SUPERCEDE);
	}
	RETURN_META(MRES_IGNORED);
}
