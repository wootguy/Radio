
class PacketListener {
	uint packetId; // packet id that indicates a song has started
	uint songId; // song that was started
}

class Channel {
	string name;
	int id = -1;
	int maxStreams = 4; // max videso that can be played at the same time
	array<Song@> queue;
	array<Song@> activeSongs; // songs playing at the same time
	string currentDj; // steam id
	
	bool spamMode = false; // no DJs allowed. spammers and stoppers fight to the death
	array<Song@> songsLeft; // songs left to play in auto dj queue
	
	float emptyTime = 0; // time the channel became inactive
	bool wasEmpty = false; // true if the channel was doing nothing last update
	
	float lastSongRequest = 0;
	Song songRequest; // song to be requested
	string requester;
	
	array<PacketListener> packetListeners;
	array<VoicePacket> packetStream;
	
	void think() {		
		for (uint i = 0; i < activeSongs.size(); i++) {
			if (activeSongs[i].isFinished()) {
				activeSongs.removeAt(i);
				i--;
				continue;
			}
			
			if (activeSongs[i].loadState == SONG_LOADING and g_EngineFuncs.Time() - activeSongs[i].loadTime > SONG_START_TIMEOUT) {
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
					
					activeSongs.removeAt(i);
					i--;
					
					playSong(restartSong);
					
					continue;
				} else {
					activeSongs[i].loadState = SONG_FAILED;
					announce("Failed to detect video load even after restarting it.");
				}
			}
		}
		
		CBasePlayer@ dj = getDj();
		if (dj !is null) {
			if (g_EngineFuncs.Time() - emptyTime > g_djIdleTime.GetInt()) {
				announce("DJ " + dj.pev.netname + " was ejected for inactivity.\n");
				PlayerState@ djState = getPlayerState(dj);
				djState.lastDjToggle = g_Engine.time + 10; // give someone else a chance to DJ
				currentDj = "";
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
					
					array<CBasePlayer@> listeners = getChannelListeners();
					for (uint i = 0; i < listeners.size(); i++) {
						AmbientMusicRadio::toggleMapMusic(listeners[i], true);
					}
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
		params.holdTime = 1.0f;
		params.r1 = 255;
		params.g1 = 255;
		params.b1 = 255;
		
		params.x = -1;
		params.y = 0.0001;
		params.channel = 2;

		CBasePlayer@ dj = getDj();
		string djName = dj !is null ? " - " + dj.pev.netname : "";
		
		if (isDjReserved()) {
			int reserveTimeLeft = int(Math.Ceil(g_djReserveTime.GetInt() - g_Engine.time));
			djName = " - Waiting " + reserveTimeLeft + "s for DJ";
		}
		
		string msg = name + djName + " (" + getChannelListeners(true).size() + " listening)";
		string songStr = "";
		
		if (state.muteMode == MUTE_VIDEOS) {
			msg += " **MUTED**";
		}
		
		uint maxLines = 3;
		
		for (uint i = 0; i < activeSongs.size() and i < maxLines; i++) {
			Song@ song = activeSongs[i];
			if (i > 0) {
				songStr += "\n";
			}
			int timePassed = song.getTimePassed() + (song.offset/1000);
			int songLength = (song.lengthMillis + 999) / 1000;
			string timeStr = "(" + formatTime(timePassed) + " / " + formatTime(songLength) + ")";
			
			if (song.lengthMillis == uint(-1*1000)) {
				timeStr = "(" + formatTime(timePassed) + ")";
			}
			
			string timeleft = song.loadState == SONG_LOADED ? timeStr : "(--:-- / --:--)";
			songStr += song.getClippedName(96, true) + "  " + timeleft;
		}
		
		if (activeSongs.size() > maxLines) {
			songStr += "\n+" + (activeSongs.size() - maxLines) + " others";
		}
		
		g_PlayerFuncs.HudMessage(plr, params, msg + "\n" + songStr);
	}
	
	string getCurrentSongString() {
		string label = "";
		
		if (activeSongs.size() > 0) {
			label += "\\w" + activeSongs[0].getClippedName(48, true);
			
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
		
	void triggerPacketEvents(uint packetId) {
		for (uint i = 0; i < packetListeners.size(); i++) {
			if (packetListeners[i].packetId <= packetId) { // TODO: this will break when packet id overflows
				Song@ song = findSongById(packetListeners[i].songId);
			
				if (song !is null) {
					println("packet " + packetId + " triggered start of song " + packetListeners[i].songId);
					
					if (song.loadState != SONG_LOADED) {
						RelaySay(name + "|" + song.getName(false) + "|" + (getDj() !is null ? string(getDj().pev.netname) : "(none)"));
						advertise("Now playing: " + song.getName(false));
						
						g_EngineFuncs.ServerPrint("[Radio] " + song.getName(false) + "\n");
						g_Game.AlertMessage(at_logged, "[Radio] " + song.getName(false) + "\n");
						
						g_EngineFuncs.ServerPrint("[Radio] " + song.path + "\n");
						g_Game.AlertMessage(at_logged, "[Radio] " + song.path + "\n");
					}
					
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
		CBasePlayer@ dj = getDj();
		return (dj is null and !isDjReserved()) or (dj !is null and dj.entindex() == plr.entindex());
	}
	
	bool requestSong(CBasePlayer@ plr, Song song) {
		PlayerState@ djState = getPlayerState(getDj());
		if (!djState.requestsAllowed) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] " + getDj().pev.netname + " doesn't take requests.\n");
			return false;
		}
	
		
		if (g_EngineFuncs.Time() - lastSongRequest < SONG_REQUEST_TIMEOUT) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] " + getDj().pev.netname + " is busy handling another request.\n");
			return false;
		}
	
		lastSongRequest = g_EngineFuncs.Time();
		songRequest = song;
		requester = plr.pev.netname;
		
		send_voice_server_message("Radio\\en\\100\\.info " + id + " " + song.id + " " + song.path);
		return true;
	}
	
	void announce(string msg, HUD messageType=HUD_PRINTTALK, CBasePlayer@ exclude=null) {
		array<CBasePlayer@> listeners = getChannelListeners();
		
		for (uint i = 0; i < listeners.size(); i++) {
			if (exclude is null or (listeners[i].entindex() != exclude.entindex())) {
				g_PlayerFuncs.ClientPrint(listeners[i], messageType, "[Radio] " + msg + "\n");
			}
		}
	}
	
	void advertise(string msg, HUD messageType=HUD_PRINTNOTIFY) {
		for ( int i = 1; i <= g_Engine.maxClients; i++ )
		{
			CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (plr is null or !plr.IsConnected()) {
				continue;
			}
			
			PlayerState@ state = getPlayerState(plr);
			
			// advertise to players in who are not listening to anything, or if their channel has nothing playing
			if (state.channel == -1 or g_channels[state.channel].activeSongs.size() == 0) {
				g_PlayerFuncs.ClientPrint(plr, messageType, "[Radio][" + name + "] " + msg + "\n");
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
		
		updateSleepState();
	}
	
	void playSong(Song song) {
		song.isPlaying = true;
		song.loadState = SONG_LOADING;
		song.loadTime = g_EngineFuncs.Time();
		activeSongs.insertLast(song);
		send_voice_server_message("Radio\\en\\100\\" + song.path + " " + id + " " + song.id + " " + song.args);
		
		array<CBasePlayer@> listeners = getChannelListeners();
		for (uint i = 0; i < listeners.size(); i++) {
			AmbientMusicRadio::toggleMapMusic(listeners[i], false);
		}
	}
	
	void cancelSong(uint songId, string reason) {
		Song@ song = findSongById(songId);
		
		if (song !is null) {
			song.loadState = SONG_FAILED;
			announce("Failed to play: " + song.path + "\n");
			g_Log.PrintF("Failed to play: " + song.path + "\n");
			
			if (reason.Length() > 0) {
				announce(reason + "\n");
				g_Log.PrintF(reason + "\n");
			}
		} else {
			println("Failed to cancel song with id " + songId);
		}
	}
	
	void finishSong(uint songId) {
		Song@ song = findSongById(songId);
		
		if (song !is null) {
			song.loadState = SONG_FINISHED;
		} else {
			println("Failed to finish song with id " + songId);
		}
	}
	
	void stopMusic(CBasePlayer@ skipper, int excludeIdx, bool clearQueue) {
		if (skipper !is null) {
			PlayerState@ state = getPlayerState(skipper);
			
			if (!canDj(skipper)) {
				g_PlayerFuncs.ClientPrint(skipper, HUD_PRINTTALK, "[Radio] Only the DJ can stop videos.\n");
				return;
			}
			
			if (state.shouldSongSkipCooldown(skipper)) {
				return;
			}
			
			if (activeSongs.size() == 0) {
				g_PlayerFuncs.ClientPrint(skipper, HUD_PRINTTALK, "[Radio] No videos are playing.\n");
				return;
			}
			
			state.lastSongSkip = g_Engine.time;
		}
	
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
				
				if (numStopped == 0) {
					g_PlayerFuncs.ClientPrint(skipper, HUD_PRINTTALK, "Only one video is playing.");
				} else {
					announce(msg);
				}
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
	
	bool queueSong(CBasePlayer@ plr, Song song) {	
		if (int(queue.size()) >= g_maxQueue.GetInt()) {
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
						announce("" + song.requester + " played: " + song.getName(false));
						announce("" + song.requester + " played: " + song.path + " " + song.args, HUD_PRINTCONSOLE);
					} else {
						announce("Now playing: " + song.getName(false)); // TODO: don't show this if hud is enabled
						announce("Now playing: " + song.path + " " + song.args, HUD_PRINTCONSOLE);
					}
					song.messageSent = true;
				}
				song.startTime = DateTime(); // don't skip the song if the video was restarted at an offset due to an error
			} else if (!song.messageSent) {
				song.messageSent = true;
				announce("" + song.requester + " queued: " + song.getName(false), currentDj.Length() == 0 ? HUD_PRINTTALK : HUD_PRINTNOTIFY);
				announce("" + song.requester + " queued: " + song.path + " " + song.args, HUD_PRINTCONSOLE);
			}
			
			return;
		}
		
		if (songRequest.id == songId) {
			songRequest.title = title;
			songRequest.lengthMillis = duration*1000;
			songRequest.offset = offset*1000;
			
			announce("" + requester + " requested: " + songRequest.title);
			announce("" + requester + " requested: " + songRequest.path, HUD_PRINTCONSOLE);
			openMenuSongRequest(EHandle(getDj()), requester, songRequest.getClippedName(64, true), id);
			return;
		}
		
		println("Got info for songId " + songId + " which isn't queued in channel: " + name);
	}
	
	array<CBasePlayer@> getChannelListeners(bool excludeVideoMuters=false) {
		array<CBasePlayer@> listeners;
		
		for ( int i = 1; i <= g_Engine.maxClients; i++ )
		{
			CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (plr is null or !plr.IsConnected()) {
				continue;
			}
			
			PlayerState@ state = getPlayerState(plr);
			
			if (excludeVideoMuters and state.muteMode == MUTE_VIDEOS) {
				continue;
			}
			
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