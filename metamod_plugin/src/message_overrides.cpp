#include "message_overrides.h"
#include "TextMenu.h"

bool shouldSuppressMapMusic(int msg_dest, int msg_type, const float* pOrigin, edict_t* ed) {
	return false;
}

void MessageBegin(int msg_dest, int msg_type, const float* pOrigin, edict_t* ed) {
	TextMenuMessageBeginHook(msg_dest, msg_type, pOrigin, ed);

	if (shouldSuppressMapMusic(msg_dest, msg_type, pOrigin, ed)) {
		RETURN_META(MRES_SUPERCEDE);
	}
	RETURN_META(MRES_IGNORED);
}