#include "mmlib.h"
#include "menus.h"
#include "radio.h"
#include "Channel.h"

void callbackMenuRadio(TextMenu* menu, edict_t* plr, int itemNumber, TextMenuItem& item) {
	PlayerState& state = getPlayerState(plr);
	int playerid = g_engfuncs.pfnGetPlayerUserId(plr);

	bool canDj = true;
	Channel* chan = NULL;
	if (state.channel >= 0 && state.channel < g_channelCount->value) {
		canDj = g_channels[state.channel].canDj(plr);
		chan = &g_channels[state.channel];
	}

	string option = item.data;

	if (option == "channels") {
		g_Scheduler.SetTimeout(openMenuChannelSelect, 0.0f, playerid);
	}
	else if (option == "turn-off") {
		state.channel = -1;

		if (chan) {
			chan->handlePlayerLeave(plr, -1);
		}

		string msg = "[Radio] Turned off.";
		if (state.neverUsedBefore) {
			state.neverUsedBefore = false;
			msg += " Say .radio to turn it back on.";
		}

		ClientPrint(plr, HUD_PRINTTALK, string(msg + "\n").c_str());
		clientCommand(plr, "mp3 stop");

		hudtextparms_t params = { 0 };
		params.holdTime = 0.5f;
		params.x = -1;
		params.y = 0.0001;
		params.channel = 2;

		HudMessage(plr, params, "");

		toggleMapMusic(plr, true);
	}
	else if (option == "main-menu") {
		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
	}
	else if (option == "toggle-mute") {
		state.muteMode = (state.muteMode + 1) % MUTE_MODES;
		clientCommand(plr, "stopsound"); // switching too fast can cause stuttering
		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
	}
	else if (option == "stop-menu" && chan) {
		if (chan->activeSongs.size() < 1) {
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] No videos are playing.\n");
			g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
			return;
		}

		if (!canDj) {
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] Only the DJ can stop videos.\n");
			g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
			return;
		}

		g_Scheduler.SetTimeout(openMenuStopVideo, 0.0f, playerid);
	}
	else if (option == "edit-queue" && chan) {
		if (chan->queue.size() < 1) {
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] The queue is empty.\n");
			g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
			return;
		}
		g_Scheduler.SetTimeout(openMenuEditQueue, 0.0f, playerid, -1);
	}
	else if (option == "become-dj" && chan) {
		edict_t* currentDj = chan->getDj();

		if (chan->isDjReserved()) {
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] DJ slot is reserved by someone who hasn't finished joining yet.\n");
			g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
			return;
		}

		if (chan->spamMode) {
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] The DJ feature is disabled in this channel.\n");
			g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
			return;
		}

		if (state.shouldDjToggleCooldown(plr)) {
			g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
			return;
		}

		if (currentDj) {
			if (ENTINDEX(currentDj) != ENTINDEX(plr)) {
				ClientPrint(plr, HUD_PRINTTALK, (string("[Radio] ") + STRING(currentDj->v.netname) + " must stop DJ'ing first.\n").c_str());
			}
			else {
				chan->announce((string(STRING(currentDj->v.netname)) + " is not the DJ anymore.\n").c_str());
				chan->currentDj = "";
			}
		}
		else {
			chan->currentDj = getPlayerUniqueId(plr);
			state.requestsAllowed = true;
			chan->emptyTime = g_engfuncs.pfnTime(); // prevent immediate ejection
			chan->announce(string(STRING(plr->v.netname)) + " is now the DJ!");
		}
		state.lastDjToggle = gpGlobals->time;

		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
	}
	else if (option == "invite") {
		g_Scheduler.SetTimeout(openMenuInvite, 0.0f, playerid);
	}
	else if (option == "hud") {
		state.showHud = !state.showHud;

		ClientPrint(plr, HUD_PRINTTALK, (string("[Radio] HUD ") + (state.showHud ? "enabled" : "disabled") + ".\n").c_str());

		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
	}
	else if (option == "help") {
		showConsoleHelp(plr, true);
		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
	}
	else {
		if (state.neverUsedBefore) {
			state.neverUsedBefore = false;
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] Say .radio if you want to re-open the menu.\n");
		}
	}
}

void joinRadioChannel(edict_t* plr, int newChannel) {
	PlayerState& state = getPlayerState(plr);
	int playerid = g_engfuncs.pfnGetPlayerUserId(plr);

	int oldChannel = state.channel;
	state.channel = newChannel;

	g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);

	if (oldChannel == state.channel) {
		return;
	}

	if (oldChannel >= 0) {
		g_channels[oldChannel].handlePlayerLeave(plr, state.channel);
	}

	bool musicIsPlaying = g_channels[state.channel].activeSongs.size() > 0;

	clientCommand(plr, "stopsound");

	toggleMapMusic(plr, !musicIsPlaying);

	g_channels[state.channel].announce(string(STRING(plr->v.netname)) + " tuned in.", HUD_PRINTNOTIFY, plr);
	updateSleepState();
}

void callbackMenuChannelSelect(TextMenu* menu, edict_t* plr, int itemNumber, TextMenuItem& item) {
	PlayerState& state = getPlayerState(plr);

	string chanPrefix = "channel-";
	string option = item.data;

	if (option.find(chanPrefix) == 0) {
		int newChannel = atoi(option.substr(chanPrefix.length(), option.find(":")).c_str());

		if (int(option.find(":invited")) != -1) {
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] This menu is opened by saying .radio\n");
		}

		joinRadioChannel(plr, newChannel);
	}
	else if (option.find("block-request") == 0) {
		state.blockInvites = true;
		ClientPrint(plr, HUD_PRINTTALK, "[Radio] You will no longer receive radio invites.\n");
	}
}

void callbackMenuRequest(TextMenu* menu, edict_t* plr, int itemNumber, TextMenuItem& item) {
	PlayerState& state = getPlayerState(plr);

	if (state.channel < 0 || state.channel >= g_channelCount->value) {
		return;
	}

	Channel& chan = g_channels[state.channel];
	bool canDj = chan.canDj(plr);

	string option = item.data;

	if (option.find("play-request") == 0) {
		vector<string> parts = splitString(option, ":");
		int channelId = atoi(parts[1].c_str());
		g_channels[channelId].announce("Request will be played now: " + g_channels[channelId].songRequest.title, HUD_PRINTCONSOLE);
		g_channels[channelId].songRequest.requester = STRING(plr->v.netname);
		g_channels[channelId].playSong(g_channels[channelId].songRequest);
		g_channels[channelId].songRequest.id = 0;

		g_channels[channelId].lastSongRequest = 0;

	}
	else if (option.find("queue-request") == 0) {
		vector<string> parts = splitString(option, ":");
		int channelId = atoi(parts[1].c_str());
		g_channels[channelId].songRequest.requester = STRING(plr->v.netname);
		g_channels[channelId].queueSong(plr, g_channels[channelId].songRequest);
		g_channels[channelId].songRequest.id = 0;

		g_channels[channelId].lastSongRequest = 0;

	}
	else if (option.find("deny-request") == 0) {
		vector<string> parts = splitString(option, ":");
		int channelId = atoi(parts[1].c_str());

		g_channels[channelId].songRequest.id = 0;
		g_channels[channelId].lastSongRequest = 0;
		g_channels[channelId].announce(string(STRING(plr->v.netname)) + " denied the request.", HUD_PRINTNOTIFY);
	}
	else if (option.find("block-request") == 0) {
		vector<string> parts = splitString(option, ":");
		int channelId = atoi(parts[1].c_str());

		state.requestsAllowed = false;
		g_channels[channelId].announce(string(STRING(plr->v.netname)) + " is no longer taking requests.");
	}
}

void callbackMenuEditQueue(TextMenu* menu, edict_t* plr, int itemNumber, TextMenuItem& item) {
	PlayerState& state = getPlayerState(plr);
	int playerid = g_engfuncs.pfnGetPlayerUserId(plr);

	if (state.channel < 0 || state.channel >= g_channelCount->value) {
		return;
	}

	Channel& chan = g_channels[state.channel];
	bool canDj = chan.canDj(plr);

	string option = item.data;

	if (option == "main-menu") {
		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
		return;
	}

	if (!canDj) {
		g_Scheduler.SetTimeout(openMenuEditQueue, 0.0f, playerid, -1);
		ClientPrint(plr, HUD_PRINTTALK, "[Radio] Only the DJ can edit the queue.\n");
		return;
	}

	if (option.find("edit-slot-") == 0) {
		int slot = atoi(option.substr(10).c_str());

		if (!canDj) {
			slot = 0;
		}

		g_Scheduler.SetTimeout(openMenuEditQueue, 0.0f, playerid, slot);
	}
	else if (option.find("move-up-") == 0) {
		int slot = atoi(option.substr(8).c_str());
		int newSlot = slot;

		if (slot > 0) {
			chan.announce(string(STRING(plr->v.netname)) + " moved up: " + chan.queue[slot].getName(false), HUD_PRINTNOTIFY);
			Song temp = Song(chan.queue[slot]);
			chan.queue[slot] = Song(chan.queue[slot - 1]);
			chan.queue[slot - 1] = Song(temp);
			newSlot = slot - 1;
		}

		g_Scheduler.SetTimeout(openMenuEditQueue, 0.0f, playerid, newSlot);
	}
	else if (option.find("move-down-") == 0) {
		int slot = atoi(option.substr(10).c_str());
		int newSlot = slot;

		if (slot < int(chan.queue.size()) - 1) {
			chan.announce(string(STRING(plr->v.netname)) + " moved down: " + chan.queue[slot].getName(false), HUD_PRINTNOTIFY);
			Song temp = Song(chan.queue[slot]);
			chan.queue[slot] = Song(chan.queue[slot + 1]);
			chan.queue[slot + 1] = Song(temp);
			newSlot = slot + 1;
		}

		g_Scheduler.SetTimeout(openMenuEditQueue, 0.0f, playerid, newSlot);
	}
	else if (option.find("remove-") == 0) {
		int slot = atoi(option.substr(7).c_str());

		if (slot < int(chan.queue.size())) {
			int msgType = chan.hasDj() ? HUD_PRINTNOTIFY : HUD_PRINTTALK;
			chan.announce(string(STRING(plr->v.netname)) + " removed: " + chan.queue[slot].getName(false), msgType);
			chan.queue.erase(chan.queue.begin() + slot);
		}

		g_Scheduler.SetTimeout(openMenuEditQueue, 0.0f, playerid, -1);
	}
	else if (option == "edit-queue") {
		g_Scheduler.SetTimeout(openMenuEditQueue, 0.0f, playerid, -1);
	}
}

void callbackMenuStopVideo(TextMenu* menu, edict_t* plr, int itemNumber, TextMenuItem& item) {
	PlayerState& state = getPlayerState(plr);
	int playerid = g_engfuncs.pfnGetPlayerUserId(plr);

	if (state.channel < 0 || state.channel >= g_channelCount->value) {
		return;
	}

	Channel& chan = g_channels[state.channel];
	bool canDj = chan.canDj(plr);

	string option = item.data;

	if (option.find("main-menu") == 0) {
		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
	}

	if (option.find("stop-") == 0) {
		g_Scheduler.SetTimeout(openMenuStopVideo, 0.0f, playerid);

		if (option.find("stop-all") == 0) {
			chan.stopMusic(plr, -1, false);
		}
		else if (option.find("stop-last") == 0) {
			chan.stopMusic(plr, 0, false);
		}
		else if (option.find("stop-first") == 0) {
			chan.stopMusic(plr, chan.activeSongs.size() - 1, false);
		}
		else if (option.find("stop-and-clear-queue") == 0) {
			chan.stopMusic(plr, -1, true);
		}
	}
}

void callbackMenuInvite(TextMenu* menu, edict_t* plr, int itemNumber, TextMenuItem& item) {
	PlayerState& state = getPlayerState(plr);
	int playerid = g_engfuncs.pfnGetPlayerUserId(plr);

	if (state.channel < 0 || state.channel >= g_channelCount->value) {
		return;
	}

	Channel& chan = g_channels[state.channel];
	bool canDj = chan.canDj(plr);

	string option = item.data;

	if (option == "inviteall") {
		int inviteCount = 0;

		if (state.shouldInviteCooldown(plr, "\\everyone")) {
			g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
			return;
		}

		for (int i = 1; i <= gpGlobals->maxClients; i++) {
			edict_t* target = INDEXENT(i);

			if (!isValidPlayer(target) || ENTINDEX(target) == ENTINDEX(plr)) {
				continue;
			}
			PlayerState& targetState = getPlayerState(target);
			int targetid = g_engfuncs.pfnGetPlayerUserId(target);

			if (targetState.channel == state.channel) {
				continue;
			}
			if (targetState.blockInvites) {
				ClientPrint(target, HUD_PRINTNOTIFY, (string("[Radio] Blocked invite from ") + STRING(plr->v.netname) + "\n").c_str());
				continue;
			}

			g_Scheduler.SetTimeout(openMenuInviteRequest, 0.5f, targetid, string(STRING(plr->v.netname)), state.channel);
			inviteCount++;
		}

		if (inviteCount == 0) {
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] No one to invite.\n");
		}
		else {
			state.lastInviteTime["\\everyone"] = gpGlobals->time;
			chan.announce(string(STRING(plr->v.netname)) + " invited " + to_string(inviteCount) + " players");
		}

		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
	}
	else if (option.find("invite-") == 0) {
		string targetId = option.substr(7);
		edict_t* target = getPlayerByUniqueId(targetId);
		int targetidnum = g_engfuncs.pfnGetPlayerUserId(target);

		if (state.shouldInviteCooldown(plr, targetId)) {
			g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
			return;
		}

		if (target) {
			PlayerState& targetState = getPlayerState(target);

			if (!targetState.blockInvites) {
				g_Scheduler.SetTimeout(openMenuInviteRequest, 0.5f, targetidnum, string(STRING(plr->v.netname)), state.channel);

				ClientPrint(plr, HUD_PRINTTALK, (string("[Radio] Invitation sent to ") + STRING(target->v.netname) + "\n").c_str());

				state.lastInviteTime[targetId] = gpGlobals->time;
			}
			else {
				ClientPrint(plr, HUD_PRINTTALK, (string("[Radio] ") + STRING(target->v.netname) + " has blocked invites.\n").c_str());
			}
		}
		else {
			ClientPrint(plr, HUD_PRINTTALK, "[Radio] Invitation failed. Player left the game.\n");
		}

		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
	}
	else if (option.find("invite-decline-") == 0) {
		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
	}
	else if (option == "main-menu") {
		g_Scheduler.SetTimeout(openMenuRadio, 0.0f, playerid);
	}
}



void openMenuRadio(int playerid) {
	edict_t* plr = getPlayerByUserId(playerid);
	if (!plr) {
		return;
	}

	int eidx = ENTINDEX(plr);
	PlayerState& state = getPlayerState(plr);
	if (state.channel < 0 || state.channel >= g_channelCount->value) {
		return;
	}
	Channel& chan = g_channels[state.channel];

	TextMenu& menu = initMenuForPlayer(plr, callbackMenuRadio);

	if (g_channelCount->value > 1) {
		menu.SetTitle("\\yRadio - " + chan.name);
	}
	else {
		menu.SetTitle("\\yRadio");
	}


	edict_t* dj = chan.getDj();
	bool isDjReserved = chan.isDjReserved();
	bool canDj = chan.canDj(plr);
	bool isDj = dj && ENTINDEX(dj) == ENTINDEX(plr);

	string muted = "\\d(off)";
	if (state.muteMode == MUTE_TTS) {
		muted = "speech";
	}
	else if (state.muteMode == MUTE_VIDEOS) {
		muted = "videos";
	}

	menu.AddItem("\\wHelp\\y", "help");
	menu.AddItem("\\wTurn off\\y", "turn-off");
	if (g_channelCount->value > 1) {
		menu.AddItem("\\wChange channel\\y", "channels");
	}
	menu.AddItem("\\w" + string(canDj ? "Edit" : "View") + " queue  " + chan.getQueueCountString() + "\\y", "edit-queue");
	menu.AddItem("\\wStop video(s)\\y", "stop-menu");
	menu.AddItem("\\wHUD: " + string(state.showHud ? "on" : "off") + "\\y", "hud");
	menu.AddItem("\\wMute: " + muted + "\\y", "toggle-mute");
	menu.AddItem((chan.spamMode ? "\\d" : "\\w") + string(isDj ? "Quit DJ" : "Become DJ") + "\\y", "become-dj");
	menu.AddItem("\\wInvite\\y", "invite");

	menu.Open(0, 0, plr);
}

void openMenuStopVideo(int playerid) {
	edict_t* plr = getPlayerByUserId(playerid);
	if (!plr) {
		return;
	}

	int eidx = ENTINDEX(plr);
	PlayerState& state = getPlayerState(plr);
	if (state.channel < 0 || state.channel >= g_channelCount->value) {
		return;
	}
	Channel& chan = g_channels[state.channel];

	TextMenu& menu = initMenuForPlayer(plr, callbackMenuStopVideo);
	menu.SetTitle("\\y" + chan.name + " - Stop video(s)");

	edict_t* dj = chan.getDj();
	bool isDjReserved = chan.isDjReserved();
	bool canDj = chan.canDj(plr);
	bool isDj = dj && ENTINDEX(dj) == ENTINDEX(plr);

	menu.AddItem("\\w..\\y", "main-menu");
	menu.AddItem("\\wStop all videos\\y", "stop-all");
	menu.AddItem("\\wStop all videos except the first\\y", "stop-last");
	menu.AddItem("\\wStop all videos except the last\\y", "stop-first");
	menu.AddItem("\\wStop all videos and clear the queue\\y", "stop-and-clear-queue");

	menu.Open(0, 0, plr);
}

void openMenuChannelSelect(int playerid) {
	edict_t* plr = getPlayerByUserId(playerid);
	if (!plr) {
		return;
	}

	int eidx = ENTINDEX(plr);
	PlayerState& state = getPlayerState(plr);

	TextMenu& menu = initMenuForPlayer(plr, callbackMenuChannelSelect);
	menu.SetTitle("\\yRadio Channels\n");

	for (int i = 0; i < g_channelCount->value; i++) {
		Channel& chan = g_channels[i];
		string label = "\\w" + chan.name;

		vector<edict_t*> listeners = chan.getChannelListeners();

		edict_t* dj = chan.getDj();

		if (listeners.size() > 0) {
			label += "\\d  (" + to_string(listeners.size()) + " listening)";
		}

		string djName = dj ? string(STRING(dj->v.netname)) : "\\d(none)";

		label += "\n\\y      Current DJ:\\w " + (chan.spamMode ? "\\d(disabled)" : djName);
		label += "\n\\y      Now Playing:\\w " + chan.getCurrentSongString();

		label += "\n\\y";

		menu.AddItem(label, string("channel-") + to_string(i));
	}

	menu.Open(0, 0, plr);
}

void openMenuEditQueue(int playerid, int selectedSlot) {
	edict_t* plr = getPlayerByUserId(playerid);
	if (!plr) {
		return;
	}

	int eidx = ENTINDEX(plr);
	PlayerState& state = getPlayerState(plr);
	if (state.channel < 0 || state.channel >= g_channelCount->value) {
		return;
	}
	Channel& chan = g_channels[state.channel];

	string title = chan.canDj(plr) ? "Edit queue" : "View queue";

	TextMenu& menu = initMenuForPlayer(plr, callbackMenuEditQueue);

	if (selectedSlot == -1) {
		menu.SetTitle("\\y" + chan.name + " - " + title);
		menu.AddItem("\\w..\\y", "main-menu");

		for (int i = 0; i < chan.queue.size(); i++) {
			string label = "\\w" + chan.queue[i].getClippedName(48, true) + "\\y";

			// try to keep the menu spacing the same in both edit modes
			if (i == chan.queue.size() - 1) {
				if (chan.queue.size() <= 2) {
					label += "\n\n\n\n";
				}
				else {
					label += "\n\n\n\n";

					if (chan.queue.size() > 0) {
						label += "\n\n\n";
					}
					if (chan.queue.size() > 4) {
						label += "\n\n";
					}
				}
			}

			menu.AddItem(label, "edit-slot-" + to_string(i));
		}
	}
	else {
		string label = "\\y" + chan.name + " - " + title + "\n";

		for (int i = 0; i < chan.queue.size(); i++) {
			string color = int(i) == selectedSlot ? "\\r" : "\\w";
			string name = int(i) == selectedSlot ? chan.queue[i].getClippedName(120, true) : chan.queue[i].getClippedName(32, true);
			label += "\n" + color + "    " + name + "\\y";
		}

		label += "\n\n\\yAction:";

		menu.SetTitle(label);
		menu.AddItem("\\wCancel\\y", "edit-queue");
		menu.AddItem("\\wMove up\\y", "move-up-" + to_string(selectedSlot));
		menu.AddItem("\\wMove down\\y", "move-down-" + to_string(selectedSlot));
		menu.AddItem("\\wRemove\\y", "remove-" + to_string(selectedSlot));
	}

	menu.Open(0, 0, plr);
}

void openMenuInviteRequest(int playerid, string asker, int channel) {
	edict_t* plr = getPlayerByUserId(playerid);
	if (!isValidPlayer(plr)) {
		return;
	}

	int eidx = ENTINDEX(plr);
	PlayerState& state = getPlayerState(plr);
	if (channel < 0 || channel >= g_channelCount->value) {
		return;
	}
	Channel& chan = g_channels[channel];

	TextMenu& menu = initMenuForPlayer(plr, callbackMenuChannelSelect);

	if (g_channelCount->value > 1) {
		menu.SetTitle("\\yYou're invited to listen to\nthe radio on " + g_channels[channel].name + "\n-" + asker + "\n");
	}
	else {
		menu.SetTitle("\\yYou're invited to listen to\nthe radio\n-" + asker + "\n");
	}

	menu.AddItem("\\wAccept\\y", "channel-" + to_string(channel) + ":invited");
	menu.AddItem("\\wIgnore\\y", "exit");

	string label = "\\wBlock invites\\y";
	label += "\n\nNow playing:\n";

	label += chan.getCurrentSongString();

	menu.AddItem(label + "\\y", "block-requests");

	menu.Open(0, 0, plr);
}

void openMenuSongRequest(int playerid, string asker, string songName, int channelId) {
	edict_t* plr = getPlayerByUserId(playerid);
	if (!plr) {
		return;
	}

	int eidx = ENTINDEX(plr);

	TextMenu& menu = initMenuForPlayer(plr, callbackMenuRequest);
	menu.SetTitle("\\yRadio request from \"" + asker + "\":\n\n" + songName + "\n");

	menu.AddItem("\\wPlay now\\y", "play-request:" + to_string(channelId));
	menu.AddItem("\\wAdd to queue\\y", "queue-request:" + to_string(channelId));
	menu.AddItem("\\wDeny request\\y", "deny-request:" + to_string(channelId));
	menu.AddItem("\\wDisable requests\\y", "block-request:" + to_string(channelId));

	menu.Open(SONG_REQUEST_TIMEOUT, 0, plr);
}

void openMenuInvite(int playerid) {
	edict_t* plr = getPlayerByUserId(playerid);
	if (!plr) {
		return;
	}

	int eidx = ENTINDEX(plr);
	PlayerState& state = getPlayerState(plr);
	if (state.channel < 0 || state.channel >= g_channelCount->value) {
		return;
	}
	Channel& chan = g_channels[state.channel];

	TextMenu& menu = initMenuForPlayer(plr, callbackMenuInvite);
	menu.SetTitle("\\y" + chan.name + " - Invite");

	menu.AddItem("\\w..\\y", "main-menu");
	menu.AddItem("\\rEveryone\\y", "inviteall");

	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* target = INDEXENT(i);

		if (!isValidPlayer(target) || ENTINDEX(target) == ENTINDEX(plr)) {
			continue;
		}

		PlayerState& targetState = getPlayerState(target);
		if (targetState.channel == state.channel) {
			continue;
		}
		string color = targetState.blockInvites ? "\\d" : "\\w";

		menu.AddItem(color + STRING(target->v.netname) + "\\y", "invite-" + getPlayerUniqueId(target));
	}

	menu.Open(0, 0, plr);
}

