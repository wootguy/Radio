#include "Channel.h"
#include "radio.h"
#include "menus.h"

void Channel::think() {
	for (int i = 0; i < activeSongs.size(); i++) {
		if (activeSongs[i].isFinished()) {
			activeSongs.erase(activeSongs.begin() + i);
			i--;
			continue;
		}

		if (activeSongs[i].loadState == SONG_LOADING && g_engfuncs.pfnTime() - activeSongs[i].loadTime > SONG_START_TIMEOUT) {
			// voice server probably loaded it so stop it
			send_voice_server_message("Radio\\en\\100\\.stopid " + activeSongs[i].id);

			if (!activeSongs[i].noRestart) {
				// attempt to restart song
				Song restartSong;
				restartSong.path = activeSongs[i].path;
				restartSong.loadState = activeSongs[i].loadState;
				restartSong.offset = activeSongs[i].offset;
				restartSong.id = g_song_id;
				restartSong.requester = activeSongs[i].requester;
				restartSong.args = activeSongs[i].args;
				restartSong.noRestart = true; // only try this once
				g_song_id += 1;

				announce("Video seems to have never started. Attempting to restart it.");

				activeSongs.erase(activeSongs.begin() + i);
				i--;

				playSong(restartSong);

				continue;
			}
			else {
				activeSongs[i].loadState = SONG_FAILED;
				announce("Failed to detect video load even after restarting it.");
			}
		}
	}

	if (areSongsFinished()) {
		if (queue.size() > 0) {
			Song song = queue[0];
			queue.erase(queue.begin() + 0);
			playSong(song);
		}
		else {
			if (!wasEmpty) {
				emptyTime = g_engfuncs.pfnTime();
				wasEmpty = true;

				vector<edict_t*> listeners = getChannelListeners();
				for (int i = 0; i < listeners.size(); i++) {
					//AmbientMusicRadio::toggleMapMusic(listeners[i], true);
					println("TODO: Resume music messages\n");
				}
			}
		}
	}
	else {
		wasEmpty = false;
	}

	edict_t* dj = getDj();
	if (dj) {
		if (wasEmpty && g_engfuncs.pfnTime() - emptyTime > g_djIdleTime->value) {
			announce(string("DJ ") + STRING(dj->v.netname) + " was ejected for inactivity.\n");
			PlayerState& djState = getPlayerState(dj);
			djState.lastDjToggle = gpGlobals->time + 10; // give someone else a chance to DJ
			currentDj = "";
		}
	}
}

void Channel::rename(edict_t* namer, string newName) {
	const int maxLength = 48;

	if (!canDj(namer)) {
		ClientPrint(namer, HUD_PRINTTALK, "[Radio] Only the DJ can rename this channel.\n");
		return;
	}

	if (newName.length() > maxLength) {
		ClientPrint(namer, HUD_PRINTTALK, UTIL_VarArgs("[Radio] Channel name must be %d characters or less.\n", maxLength));
		return;
	}

	announce(string(STRING(namer->v.netname)) + " renamed the channel to \"" + newName + "\"");
	name = newName;
}

void Channel::updateHud(edict_t* plr, PlayerState& state) {
	if (wasEmpty && g_engfuncs.pfnTime() - emptyTime > 5.0f) {
		return;
	}

	hudtextparms_t params = { 0 };
	params.effect = 0;
	params.fadeinTime = 0;
	params.fadeoutTime = 0.5f;
	params.holdTime = 1.0f;
	params.r1 = 255;
	params.g1 = 255;
	params.b1 = 255;

	params.x = -1;
	params.y = 0.0001;
	params.channel = 2;

	edict_t* dj = getDj();
	string djName = dj ? string(" - ") + STRING(dj->v.netname) : "";

	if (isDjReserved()) {
		int reserveTimeLeft = int(ceil(g_djReserveTime->value - gpGlobals->time));
		djName = " - Waiting " + to_string(reserveTimeLeft) + "s for DJ";
	}

	string msg = name + djName + " (" + to_string(getChannelListeners(true).size()) + " listening)";
	string songStr = "";

	if (state.muteMode == MUTE_VIDEOS) {
		msg += " **MUTED**";
	}

	int maxLines = 3;

	for (int i = 0; i < activeSongs.size() && i < maxLines; i++) {
		Song& song = activeSongs[i];
		if (i > 0) {
			songStr += "\n";
		}
		int timePassed = song.getTimePassed() + (song.offset / 1000);
		int songLength = (song.lengthMillis + 999) / 1000;
		string timeStr = "(" + formatTime(timePassed) + " / " + formatTime(songLength) + ")";

		if (song.lengthMillis == uint32_t(-1 * 1000) || song.lengthMillis == 0) {
			timeStr = "(" + formatTime(timePassed) + ")";
		}

		string timeleft = song.loadState == SONG_LOADED ? timeStr : "(--:-- / --:--)";
		songStr += song.getClippedName(96, true) + "  " + timeleft;
	}

	if (activeSongs.size() > maxLines) {
		songStr += UTIL_VarArgs("\n+%d others", activeSongs.size() - maxLines);
	}

	HudMessage(plr, params, (msg + "\n" + songStr).c_str());
}

string Channel::getCurrentSongString() {
	string label = "";

	if (activeSongs.size() > 0) {
		label += "\\w" + activeSongs[0].getClippedName(48, true);

		if (activeSongs.size() > 1) {
			label += UTIL_VarArgs("\\d (+%d others)", activeSongs.size() - 1);
		}

	}
	else {
		label += "\\d(nothing)";
	}

	return label;
}

bool Channel::areSongsFinished() {
	for (int i = 0; i < activeSongs.size(); i++) {
		if (!activeSongs[i].isFinished()) {
			return false;
		}
	}

	return true;
}

void Channel::triggerPacketEvents(uint32_t packetId) {
	for (int i = 0; i < packetListeners.size(); i++) {
		if (packetListeners[i].packetId <= packetId) { // TODO: this will break when packet id overflows
			Song* song = findSongById(packetListeners[i].songId);

			if (song) {
				println(UTIL_VarArgs("packet %d triggered start of song %d", packetId, packetListeners[i].songId));

				if (song->loadState != SONG_LOADED) {
					//RelaySay(name + "|" + song.getName(false) + "|" + (getDj() !is null ? string(getDj().pev.netname) : "(none)"));
					advertise("Now playing: " + song->getName(false));

					g_engfuncs.pfnServerPrint(("[Radio] " + song->getName(false) + "\n").c_str());
					logln("[Radio] " + song->getName(false));

					g_engfuncs.pfnServerPrint(("[Radio] " + song->path + "\n").c_str());
					logln("[Radio] " + song->path);
				}

				song->loadState = SONG_LOADED;
				song->startTime = g_engfuncs.pfnTime();

				int packetDiff = packetId - packetListeners[i].packetId;
				if (packetDiff > 0) {
					song->startTime = song->startTime + packetDiff * -g_packet_delay;
				}
			}
			else {
				println("packet %d triggered a non-existant song %d", packetId, packetListeners[i].songId);
			}

			packetListeners.erase(packetListeners.begin() + i);
			i--;
		}
	}
}

string Channel::getQueueCountString() {
	bool queueFull = int(queue.size()) > g_maxQueue->value;
	char * queueColor = queueFull ? "\\r" : "\\d";
	return UTIL_VarArgs("%s(%d / %d)", queueColor, queue.size(), g_maxQueue->value);
}

edict_t* Channel::getDj() {
	return getPlayerByUniqueId(currentDj);
}

bool Channel::hasDj() {
	return currentDj.length() > 0;
}

bool Channel::isDjReserved() {
	edict_t* dj = getDj();
	return !isValidPlayer(dj) && currentDj.length() > 0 && gpGlobals->time < g_djReserveTime->value;
}

bool Channel::canDj(edict_t* plr) {
	edict_t* dj = getDj();
	return (!dj && !isDjReserved()) || (dj && ENTINDEX(dj) == ENTINDEX(plr));
}

bool Channel::requestSong(edict_t* plr, Song song) {
	edict_t* dj = getDj();
	PlayerState& djState = getPlayerState(dj);
	if (dj && !djState.requestsAllowed) {
		ClientPrint(plr, HUD_PRINTTALK, (string("[Radio] ") + STRING(dj->v.netname) + " doesn't take requests.\n").c_str());
		return false;
	}


	if (dj && g_engfuncs.pfnTime() - lastSongRequest < SONG_REQUEST_TIMEOUT) {
		ClientPrint(plr, HUD_PRINTTALK, (string("[Radio] ") + STRING(dj->v.netname) + " is busy handling another request.\n").c_str());
		return false;
	}

	lastSongRequest = g_engfuncs.pfnTime();
	songRequest = song;
	requester = STRING(plr->v.netname);

	send_voice_server_message(UTIL_VarArgs("Radio\\en\\100\\.info %d %u %s", id, song.id, song.path.c_str()));
	return true;
}

void Channel::announce(string msg, int messageType, edict_t* exclude) {
	vector<edict_t*> listeners = getChannelListeners();

	for (int i = 0; i < listeners.size(); i++) {
		if (!exclude || ENTINDEX(listeners[i]) != ENTINDEX(exclude)) {
			ClientPrint(listeners[i], messageType, (string("[Radio] ") + msg + "\n").c_str());
		}
	}
}

void Channel::advertise(string msg, int messageType) {
	for (int i = 1; i < gpGlobals->maxClients; i++) {
		edict_t* plr = INDEXENT(i);

		if (!isValidPlayer(plr)) {
			continue;
		}

		PlayerState& state = getPlayerState(plr);

		// advertise to players in who are not listening to anything, or if their channel has nothing playing
		if (state.channel == -1 || g_channels[state.channel].activeSongs.size() == 0) {
			ClientPrint(plr, messageType, string("[Radio][" + name + "] " + msg + "\n").c_str());
		}
	}
}

void Channel::handlePlayerLeave(edict_t* plr, int newChannel) {
	if (newChannel >= 0) {
		announce(string(STRING(plr->v.netname)) + " switched to " + g_channels[newChannel].name + ".", HUD_PRINTNOTIFY, plr);
	}
	else {
		announce(string(STRING(plr->v.netname)) + " tuned out.", HUD_PRINTNOTIFY, plr);
	}

	if (currentDj == getPlayerUniqueId(plr)) {
		currentDj = "";
		announce(string(STRING(plr->v.netname)) + " is not the DJ anymore.", HUD_PRINTTALK, plr);
	}

	updateSleepState();
}

void Channel::playSong(Song song) {
	song.isPlaying = true;
	song.loadState = SONG_LOADING;
	song.loadTime = g_engfuncs.pfnTime();
	activeSongs.push_back(song);
	send_voice_server_message(UTIL_VarArgs("Radio\\en\\100\\%s %d %u %s", song.path.c_str(), id, song.id, song.args.c_str()));

	vector<edict_t*> listeners = getChannelListeners();
	for (int i = 0; i < listeners.size(); i++) {
		//AmbientMusicRadio::toggleMapMusic(listeners[i], false);
	}
}

void Channel::cancelSong(uint32_t songId, string reason) {
	Song* song = findSongById(songId);

	if (song) {
		song->loadState = SONG_FAILED;

		if (reason.length() > 0) {
			announce("Failed to play: " + song->path + "\n");
			logln("Failed to play: " + song->path);
			announce(reason + "\n");
			logln(reason);
		}
		else {
			// probably a temporary error, so try to start again
			if (!song->noRestart) {
				Song restartSong;
				restartSong.path = song->path;
				restartSong.loadState = SONG_UNLOADED;
				restartSong.id = g_song_id;
				restartSong.requester = song->requester;
				restartSong.args = song->args;
				restartSong.noRestart = true; // only try this once
				g_song_id += 1;

				announce("Audio failed to load, but no error reason was given. Attempting to start it again.\n", HUD_PRINTNOTIFY);

				playSong(restartSong);
			}
			else {
				announce("Failed to play: " + song->path + "\n");
				logln("Failed to play: " + song->path);
				announce("No reason was given. Maybe try again in a few seconds.\n");
			}

		}
	}
	else {
		println("Failed to cancel song with id " + songId);
	}
}

void Channel::finishSong(uint32_t songId) {
	Song* song = findSongById(songId);

	if (song) {
		song->loadState = SONG_FINISHED;
	}
	else {
		println("Failed to finish song with id " + songId);
	}
}

void Channel::stopMusic(edict_t* skipper, int excludeIdx, bool clearQueue) {
	if (skipper) {
		PlayerState& state = getPlayerState(skipper);

		if (!canDj(skipper)) {
			ClientPrint(skipper, HUD_PRINTTALK, "[Radio] Only the DJ can stop videos.\n");
			return;
		}

		if (state.shouldSongSkipCooldown(skipper)) {
			return;
		}

		if (activeSongs.size() == 0) {
			ClientPrint(skipper, HUD_PRINTTALK, "[Radio] No videos are playing.\n");
			return;
		}

		state.lastSongSkip = gpGlobals->time;
	}

	string cmd = "Radio\\en\\100\\.stopid";

	int numStopped = activeSongs.size();
	vector<Song> newActive;
	for (int i = 0; i < int(activeSongs.size()); i++) {
		if (i == excludeIdx) {
			newActive.push_back(activeSongs[i]);
			continue;
		}
		cmd += " " + activeSongs[i].id;
	}
	send_voice_server_message(cmd);
	activeSongs = newActive;

	if (skipper) {
		if (clearQueue) {
			queue.resize(0);
			announce(string(STRING(skipper->v.netname)) + " stopped all videos and cleared the queue.");
		}
		else if (excludeIdx != -1) {
			string firstLast = excludeIdx == 0 ? "first" : "last";
			string msg;
			if (currentDj.length() == 0) {
				msg = string(STRING(skipper->v.netname)) + " stopped all but the " + firstLast + " video.";
			}
			else {
				msg = "Stopped all but the " + firstLast + " video.";
			}

			if (numStopped == 0) {
				ClientPrint(skipper, HUD_PRINTTALK, "Only one video is playing.");
			}
			else {
				announce(msg);
			}
		}
		else {
			string plural = numStopped > 1 ? "Videos" : "Video";
			string action = queue.size() > 0 ? "skipped" : "stopped";
			string msg;
			if (currentDj.length() == 0) {
				msg = plural + " " + action + " by " + STRING(skipper->v.netname) + ". ";
			}
			else {
				msg = plural + " " + action + ". ";
			}
			announce(msg);
		}

	}

	vector<edict_t*> listeners = getChannelListeners();
	for (int i = 0; i < listeners.size(); i++) {
		//AmbientMusicRadio::toggleMapMusic(listeners[i], true);
	}
}

bool Channel::queueSong(edict_t* plr, Song song) {
	if (int(queue.size()) >= g_maxQueue->value) {
		ClientPrint(plr, HUD_PRINTTALK, "[Radio] Queue is full!\n");
		return false;
	}

	if (activeSongs.size() == 0) {
		// play immediately since nothing else is playing/queued			

		if (song.loadState == SONG_UNLOADED) {
			playSong(song);
		}
	}
	else {
		//announce("" + plr.pev.netname + " queued: " + song.getName(), currentDj.Length() == 0 ? HUD_PRINTTALK : HUD_PRINTNOTIFY);

		if (song.loadState == SONG_UNLOADED) {
			send_voice_server_message(UTIL_VarArgs("Radio\\en\\100\\.info %d %u %s", id, song.id, song.path.c_str()));
		}

		queue.push_back(song);
	}

	return true;
}

Song* Channel::findSongById(uint32_t songId) {
	for (int i = 0; i < queue.size(); i++) {
		Song* song = &queue[i];

		if (song->id == songId) {
			return song;
		}
	}

	for (int i = 0; i < activeSongs.size(); i++) {
		Song* song = &activeSongs[i];

		if (song->id == songId) {
			return song;
		}
	}

	return NULL;
}

void Channel::updateSongInfo(uint32_t songId, string title, int duration, int offset) {
	Song* song = findSongById(songId);

	if (song) {
		song->title = title;
		song->lengthMillis = duration * 1000;
		song->offset = offset * 1000;
		if (song->isPlaying) {
			if (!song->messageSent) {
				if (currentDj.length() == 0) {
					announce(song->requester + " played: " + song->getName(false));
					announce(song->requester + " played: " + song->path + " " + song->args, HUD_PRINTCONSOLE);
				}
				else {
					announce("Now playing: " + song->getName(false)); // TODO: don't show this if hud is enabled
					announce("Now playing: " + song->path + " " + song->args, HUD_PRINTCONSOLE);
				}
				song->messageSent = true;
			}
			song->startTime = g_engfuncs.pfnTime(); // don't skip the song if the video was restarted at an offset due to an error
		}
		else if (!song->messageSent) {
			song->messageSent = true;
			announce(song->requester + " queued: " + song->getName(false), currentDj.length() == 0 ? HUD_PRINTTALK : HUD_PRINTNOTIFY);
			announce(song->requester + " queued: " + song->path + " " + song->args, HUD_PRINTCONSOLE);
		}

		return;
	}

	if (songRequest.id == songId) {
		songRequest.title = title;
		songRequest.lengthMillis = duration * 1000;
		songRequest.offset = offset * 1000;

		announce(requester + " requested: " + songRequest.title);
		announce(requester + " requested: " + songRequest.path, HUD_PRINTCONSOLE);
		openMenuSongRequest(g_engfuncs.pfnGetPlayerUserId(getDj()), requester, songRequest.getClippedName(64, true), id);
		return;
	}

	println("Got info for songId %d which isn't queued in channel: %s", songId, name.c_str());
}

vector<edict_t*> Channel::getChannelListeners(bool excludeVideoMuters) {
	vector<edict_t*> listeners;

	for (int i = 1; i < gpGlobals->maxClients; i++) {
		edict_t* plr = INDEXENT(i);

		if (!isValidPlayer(plr)) {
			continue;
		}

		PlayerState& state = getPlayerState(plr);

		if (excludeVideoMuters && state.muteMode == MUTE_VIDEOS) {
			continue;
		}

		if (state.channel == id) {
			listeners.push_back(plr);
		}
	}

	return listeners;
}

void Channel::listenerCommand(string cmd) {
	vector<edict_t*> listeners = getChannelListeners();

	println("CHANNEL %d CMD: %s", id, cmd.c_str());

	for (int i = 0; i < listeners.size(); i++) {
		clientCommand(listeners[i], cmd);
	}
}