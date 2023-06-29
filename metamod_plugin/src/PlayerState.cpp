#include "PlayerState.h"
#include "radio.h"
#include "Channel.h"
#include "mmlib.h"

bool PlayerState::shouldInviteCooldown(edict_t* plr, string id) {
	float inviteTime = -9999;
	if (lastInviteTime.find(id) != lastInviteTime.end()) {
		inviteTime = lastInviteTime[id];
	}

	if (int(id.find("\\")) != -1) {
		id = replaceString(id, "\\", "");
	}
	else {
		edict_t* target = getPlayerByUniqueId(id);
		if (target) {
			id = STRING(target->v.netname);
		}
	}

	return shouldCooldownGeneric(plr, inviteTime, g_inviteCooldown->value, "inviting " + id + " again");
}

bool PlayerState::shouldRequestCooldown(edict_t* plr) {
	return shouldCooldownGeneric(plr, lastRequest, g_djSwapCooldown->value, "requesting another song");
}

bool PlayerState::shouldDjToggleCooldown(edict_t* plr) {
	return shouldCooldownGeneric(plr, lastDjToggle, g_djSwapCooldown->value, "toggling DJ mode again");
}

bool PlayerState::shouldSongSkipCooldown(edict_t* plr) {
	return shouldCooldownGeneric(plr, lastSongSkip, g_skipSongCooldown->value, "skipping another song");
}

bool PlayerState::shouldCooldownGeneric(edict_t* plr, float lastActionTime, int cooldownTime, string actionDesc) {
	float delta = gpGlobals->time - lastActionTime;
	if (delta < cooldownTime) {
		int waitTime = int((cooldownTime - delta) + 0.99f);
		ClientPrint(plr, HUD_PRINTTALK, (string("[Radio] Wait ") + to_string(waitTime) + " seconds before " + actionDesc + ".\n").c_str());
		return true;
	}

	return false;
}

bool PlayerState::isRadioMusicPlaying() {
	return channel >= 0 && g_channels[channel].activeSongs.size() > 0;
}

PlayerState& getPlayerState(edict_t* plr) {
	string steamId = getPlayerUniqueId(plr);

	if (g_player_states.find(steamId) == g_player_states.end()) {
		PlayerState* newState = new PlayerState();
		g_player_states[steamId] = newState;
	}

	return *g_player_states[steamId];
}
