#include "radio_utils.h"
#include "radio.h"

PlayerState* getPlayerState(string steamId) {
	if (g_player_states.find(steamId) == g_player_states.end()) {
		PlayerState* newState = new PlayerState();
		g_player_states[steamId] = newState;
	}
	
	return g_player_states[steamId];
}