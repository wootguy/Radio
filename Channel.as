
class PacketListener {
	uint packetId; // packet id that indicates a song has started
	uint songId; // song that was started
}

class Channel {
	string name;
	int id = -1;
	int maxStreams = 2; // max videso that can be played at the same time
	array<Song@> queue;
	array<Song@> activeSongs; // songs playing at the same time
	string currentDj; // steam id
	
	bool autoDj = false; // play random songs and don't let anyone dj
	bool spamMode = false; // no DJs allowed. spammers and stoppers fight to the death
	array<Song@> songsLeft; // songs left to play in auto dj queue
	
	float emptyTime = 0; // time the channel became inactive
	bool wasEmpty = false; // true if the channel was doing nothing last update
	
	array<string> mapChangeListeners;
	array<PacketListener> packetListeners;
	array<VoicePacket> packetStream;
	
	void think() {
		if (shouldWaitForListeners() > 0) {
			return;
		}
		
		for (uint i = 0; i < activeSongs.size(); i++) {
			if (activeSongs[i].isFinished()) {
				activeSongs.removeAt(i);
				i--;
			}
		}
		
		if (areSongsFinished()) {			
			if (queue.size() > 0) {				
				Song song = queue[0];
				queue.removeAt(0);
				playSong(song);
			} else {
				if (!wasEmpty) {
					emptyTime = g_EngineFuncs.Time();
					wasEmpty = true;
				}
			}
		} else {
			wasEmpty = false;
		}
	}
	
	void updateHud(CBasePlayer@ plr, PlayerState@ state) {
		if (wasEmpty && g_EngineFuncs.Time() - emptyTime > 5.0f) {
			return;
		}
		
		HUDTextParams params;
		params.effect = 0;
		params.fadeinTime = 0;
		params.fadeoutTime = 0.5f;
		params.holdTime = 2.0f;
		params.r1 = 255;
		params.g1 = 255;
		params.b1 = 255;
		
		params.x = -1;
		params.y = 0.0001;
		params.channel = 2;

		CBasePlayer@ dj = getDj();
		string djName = dj !is null ? " - " + dj.pev.netname : "";
		if (autoDj) {
			djName = " - " + AUTO_DJ_NAME;
		}
		
		if (isDjReserved()) {
			int reserveTimeLeft = int(Math.Ceil(g_djReserveTime.GetInt() - g_Engine.time));
			djName = " - Waiting " + reserveTimeLeft + "s for DJ";
		}
		
		string msg = name + djName + " (" + getChannelListeners().size() + " listening)";
		string songStr = "";
		
		if (isWaitingToPlaySong()) {
			int waitingFor = shouldWaitForListeners();
			int waitTimeLeft = int(Math.Ceil(g_listenerWaitTime.GetInt() - g_Engine.time));
			songStr = "(waiting " + waitTimeLeft + "s for " + waitingFor + " listeners)";
		} else {
			uint maxLines = 3;
			
			for (uint i = 0; i < activeSongs.size() and i < maxLines; i++) {
				Song@ song = activeSongs[i];
				if (i > 0) {
					songStr += "\n";
				}
				songStr += song.getClippedName(96) + "  " + formatTime(song.getTimeLeft());
			}
			
			if (activeSongs.size() > maxLines) {
				songStr += "\n+" + (activeSongs.size() - maxLines) + " others";
			}
		}
		
		g_PlayerFuncs.HudMessage(plr, params, msg + "\n" + songStr);
	}
	
	string getCurrentSongString() {
		string label = "";
		
		if (activeSongs.size() > 0) {
			label += "\\w" + activeSongs[0].getClippedName(48);
			
			if (activeSongs.size() > 1) {
				label += "\\d (+" + (activeSongs.size()-1) + " others)";
			}
			
		} else {
			label += "\\d(nothing)";
		}
		
		return label;
	}
	
	bool areSongsFinished() {		
		for (uint i = 0; i < activeSongs.size(); i++) {
			if (!activeSongs[i].isFinished()) {
				return false;
			}
		}
	
		return true;
	}
	
	bool isWaitingToPlaySong() {
		return areSongsFinished() and shouldWaitForListeners() > 0;
	}
	
	void rememberListeners() {
		mapChangeListeners.resize(0);
		
		array<CBasePlayer@> listeners = getChannelListeners();
		for (uint i = 0; i < listeners.size(); i++) {
			mapChangeListeners.insertLast(getPlayerUniqueId(listeners[i]));
		}
	}
	
	// returns number of listeners that haven't joined yet
	int shouldWaitForListeners() {
		int waitCount = 0;
		
		if (g_Engine.time < g_listenerWaitTime.GetInt()) {
			for (uint i = 0; i < mapChangeListeners.size(); i++) {
				CBasePlayer@ plr = getPlayerByUniqueId(mapChangeListeners[i]);
				if (plr is null or !plr.IsConnected() or g_player_lag_status[plr.entindex()] != LAG_NONE) {
					waitCount++;
				}
			}
		}
		
		return waitCount;
	}
	
	void triggerPacketEvents(uint packetId) {
		for (uint i = 0; i < packetListeners.size(); i++) {
			if (packetListeners[i].packetId <= packetId) { // TODO: this will break when packet id overflows
				Song@ song = findSongById(packetListeners[i].songId);
			
				if (song !is null) {
					println("packet " + packetId + " triggered start of song " + packetListeners[i].songId);
					song.loadState = SONG_LOADED;
					song.startTime = DateTime();
					
					int packetDiff = packetId - packetListeners[i].packetId;
					if (packetDiff > 0) {
						song.startTime = song.startTime + TimeDifference(packetDiff * -g_packet_delay);
					}
				} else {
					println("packet " + packetId + " triggered a non-existant song " + packetListeners[i].songId);
				}
				
				packetListeners.removeAt(i);
				i--;
			}
		}
	}
	
	string getSongMenuLabel(Song@ song) {
		string label = song.getName();
			
		bool isInQueue = false;
		bool nowPlaying = false;
		for (uint k = 0; k < queue.size(); k++) {
			if (queue[k].path == song.path) {
				nowPlaying = k == 0;
				isInQueue = k != 0;
				break;
			}
		}
		
		if (nowPlaying || isInQueue) {
			label = "\\r" + label;
		} else {
			label = "\\w" + label;
		}
		
		if (nowPlaying) {
			label += " \\d(now playing)";
		} else if (isInQueue) {
			label += " \\d(in queue)";
		}
		
		return label;
	}
	
	string getQueueCountString() {
		bool queueFull = int(queue.size()) > g_maxQueue.GetInt();
		string queueColor = queueFull ? "\\r" : "\\d";
		return queueColor + "(" + queue.size() + " / " + g_maxQueue.GetInt() + ")";
	}
	
	CBasePlayer@ getDj() {
		return getPlayerByUniqueId(currentDj);
	}
	
	bool hasDj() {
		return currentDj.Length() > 0;
	}
	
	bool isDjReserved() {
		CBasePlayer@ dj = getDj();
		return (dj is null or !dj.IsConnected()) and currentDj.Length() > 0 and g_Engine.time < g_djReserveTime.GetInt();
	}
	
	bool canDj(CBasePlayer@ plr) {
		if (autoDj) {
			return false;
		}
		
		CBasePlayer@ dj = getDj();
		return (dj is null and !isDjReserved()) or (dj !is null and dj.entindex() == plr.entindex());
	}
	
	void announce(string msg, HUD messageType=HUD_PRINTTALK, CBasePlayer@ exclude=null) {
		array<CBasePlayer@> listeners = getChannelListeners();
		
		for (uint i = 0; i < listeners.size(); i++) {
			if (exclude is null or (listeners[i].entindex() != exclude.entindex())) {
				g_PlayerFuncs.ClientPrint(listeners[i], messageType, "[Radio] " + msg + "\n");
			}
		}
	}
	
	void handlePlayerLeave(CBasePlayer@ plr, int newChannel) {
		if (newChannel >= 0) {
			announce("" + plr.pev.netname + " switched to " + g_channels[newChannel].name + ".", HUD_PRINTNOTIFY, plr);
		} else {
			announce("" + plr.pev.netname + " tuned out.", HUD_PRINTNOTIFY, plr);
		}
		
		if (currentDj == getPlayerUniqueId(plr)) {
			currentDj = "";
			announce("" + plr.pev.netname + " is not the DJ anymore.", HUD_PRINTTALK, plr);
		}
	}
	
	void playSong(Song@ song) {
		song.isPlaying = true;
		song.loadState = SONG_LOADING;
		activeSongs.insertLast(song);
		send_voice_server_message("Radio\\en\\100\\" + song.path + " 0:00 " + id + " " + song.id);
		
		RelaySay(name + "|" + song.getName() + "|" + (getDj() !is null ? string(getDj().pev.netname) : "(none)"));
		
		array<CBasePlayer@> listeners = getChannelListeners();
		for (uint i = 0; i < listeners.size(); i++) {
			AmbientMusicRadio::toggleMapMusic(listeners[i], false);
		}
	}
	
	void cancelSong(uint songId) {
		Song@ song = findSongById(songId);
		
		if (song !is null) {
			song.loadState = SONG_FAILED;
		} else {
			println("Failed to cancel song with id " + songId);
		}
	}
	
	void stopMusic(CBasePlayer@ skipper, int excludeIdx, bool clearQueue) {
		string cmd = "Radio\\en\\100\\.stopid";
		
		int numStopped = activeSongs.size();
		array<Song@> newActive;
		for (int i = 0; i < int(activeSongs.size()); i++) {
			if (i == excludeIdx) {
				newActive.insertLast(activeSongs[i]);
				continue;
			}
			cmd += " " + activeSongs[i].id;
		}
		send_voice_server_message(cmd);
		activeSongs = newActive;
		
		if (skipper !is null) {
			if (clearQueue) {
				queue.resize(0);
				announce("" + skipper.pev.netname + " stopped all videos and cleared the queue.");
			} else if (excludeIdx != -1) {
				string firstLast = excludeIdx == 0 ? "first" : "last";
				string msg;
				if (currentDj.Length() == 0) {
					msg = "" + skipper.pev.netname + " stopped all but the " + firstLast + " video.";
				} else {
					msg = "Stopped all but the " + firstLast + " video.";
				}
				announce(msg);
			} else {
				string plural = numStopped > 1 ? "Videos" : "Video";
				string action = queue.size() > 0 ? "skipped" : "stopped";
				string msg;
				if (currentDj.Length() == 0) {
					msg = plural + " " + action + " by " + skipper.pev.netname + ". ";
				} else {
					msg = plural + " " + action + ". ";
				}
				announce(msg);
			}
			
		}

		array<CBasePlayer@> listeners = getChannelListeners();
		for (uint i = 0; i < listeners.size(); i++) {
			AmbientMusicRadio::toggleMapMusic(listeners[i], true);
		}
	}
	
	bool queueSong(CBasePlayer@ plr, Song@ song) {	
		if (int(queue.size()) > g_maxQueue.GetInt()) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Queue is full!\n");
			return false;
		}
		
		if (activeSongs.size() == 0) {
			// play immediately since nothing else is playing/queued			
			
			if (song.loadState == SONG_UNLOADED) {
				playSong(song);
			}
		} else {
			//announce("" + plr.pev.netname + " queued: " + song.getName(), currentDj.Length() == 0 ? HUD_PRINTTALK : HUD_PRINTNOTIFY);
			
			if (song.loadState == SONG_UNLOADED) {
				send_voice_server_message("Radio\\en\\100\\.info " + id + " " + song.id + " " + song.path);
			}
			
			queue.insertLast(song);
		}
		
		return true;
	}
	
	Song@ findSongById(uint songId) {
		for (uint i = 0; i < queue.size(); i++) {
			Song@ song = queue[i];
		
			if (song.id == songId) {
				return song;
			}
		}
		
		for (uint i = 0; i < activeSongs.size(); i++) {
			Song@ song = activeSongs[i];
		
			if (song.id == songId) {
				return song;
			}
		}
		
		return null;
	}
	
	void updateSongInfo(uint songId, string title, int duration, int offset) {
		Song@ song = findSongById(songId);

		if (song !is null) {
			song.title = title;
			song.lengthMillis = duration*1000;
			song.offset = offset*1000;
			if (song.isPlaying) {
				if (!song.messageSent) {
					if (currentDj.Length() == 0) {
						announce("" + song.requester + " played: " + song.getName());
					} else {
						announce("Now playing: " + song.getName()); // TODO: don't show this if hud is enabled
					}
					song.messageSent = true;
				}
				song.startTime = DateTime(); // don't skip the song if the video was restarted at an offset due to an error
			} else if (!song.messageSent) {
				song.messageSent = true;
				announce("" + song.requester + " queued: " + song.getName(), currentDj.Length() == 0 ? HUD_PRINTTALK : HUD_PRINTNOTIFY);
			}
			
			return;
		}
		
		
		println("Got info for songId " + songId + " which isn't queued in channel: " + name);
	}
	
	array<CBasePlayer@> getChannelListeners() {
		array<CBasePlayer@> listeners;
		
		for ( int i = 1; i <= g_Engine.maxClients; i++ )
		{
			CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (plr is null or !plr.IsConnected()) {
				continue;
			}
			
			PlayerState@ state = getPlayerState(plr);
			
			if (state.channel == id) {
				listeners.insertLast(plr);
			}
		}
		
		return listeners;
	}

	void listenerCommand(string cmd) {
		array<CBasePlayer@> listeners = getChannelListeners();
		
		println("CHANNEL " + id + " CMD: " + cmd);
		
		for (uint i = 0; i < listeners.size(); i++) {
			clientCommand(listeners[i], cmd);
		}
	}
}