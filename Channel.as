
class Channel {
	string name;
	int id = -1;
	array<Song@> queue;
	string currentDj; // steam id
	DateTime startTime; // time last song was started
	string shouldSkipSong = ""; // name of player who skipped if not empty
	
	bool autoDj = false; // play random songs and don't let anyone dj
	array<Song@> songsLeft; // songs left to play in auto dj queue
	
	array<string> mapChangeListeners;
	
	void think() {
		if (shouldWaitForListeners() > 0) {
			return;
		}
		
		if (isSongFinished() or shouldSkipSong.Length() > 0) {
			if (queue.size() > 0) {
				queue.removeAt(0);
			}
			if (autoDj) {
				if (songsLeft.size() == 0) {
					generateAutoDjQueue();
				}
				queue.insertLast(songsLeft[0]);
				songsLeft.removeAt(0);
			}
			
			if (queue.size() > 0) {
				Song@ song = queue[0];
				if (shouldSkipSong.Length() > 0) {
					string msg;
					if (currentDj.Length() == 0) {
						msg = "Song skipped by " + shouldSkipSong + ". " + msg;
					} else {
						msg = "Song skipped. " + msg;
					}
					announce(msg);
				}
				
				playSong(song);
				{
					CBasePlayer@ dj = getDj();
					if (!autoDj)
						RelaySay(name + "|" + song.getName() + "|" + (dj !is null ? string(getDj().pev.netname) : "(none)"));
				}
			} else if (shouldSkipSong.Length() > 0) {
				stopMusic();
				if (currentDj.Length() == 0) {
					announce("Song stopped by " + shouldSkipSong + ".");
				} else {
					announce("Song stopped.", HUD_PRINTNOTIFY);
				}
			}
			
			shouldSkipSong = "";
		}
	}
	
	void generateAutoDjQueue() {		
		array<Song@> options;
		
		for (uint i = 0; i < g_songs.size(); i++) {
			if (float(g_songs[i].lengthMillis) > 1000*60*MAX_AUTO_DJ_SONG_LENGTH_MINUTES) {
				continue; // skip super long songs
			}
			options.insertLast(g_songs[i]);
		}
		
		songsLeft.resize(0);
		while (options.size() > 0) {
			int choice = Math.RandomLong(0, options.size()-1);
			songsLeft.insertLast(options[choice]);
			options.removeAt(choice);
		}
		
		println("Created playlist of " + songsLeft.size() + " songs");
	}
	
	void updateHud(CBasePlayer@ plr, PlayerState@ state) {
		HUDTextParams params;
		params.effect = 0;
		params.fadeinTime = 0;
		params.fadeoutTime = 0.5f;
		params.holdTime = 5.0f;
		params.r1 = 255;
		params.g1 = 255;
		params.b1 = 255;
		
		params.x = -1;
		params.y = 0.0001;
		params.channel = 2;

		Song@ song = getSong();
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
		
		if (song !is null) {
			songStr = song.getName() + "  " + formatTime(getTimeLeft());
			
			if (isWaitingToPlaySong()) {
				int waitingFor = shouldWaitForListeners();
				int waitTimeLeft = int(Math.Ceil(g_listenerWaitTime.GetInt() - g_Engine.time));
				songStr = song.getName() + "\n(waiting " + waitTimeLeft + "s for " + waitingFor + " listeners)";
			} else {
				int diff = int(TimeDifference(state.tuneTime, startTime).GetTimeDifference());
				if (diff > 0) {
					songStr += "\n(desynced by " + diff + "+ seconds)";
				}
			}
		}
		
		g_PlayerFuncs.HudMessage(plr, params, msg + "\n" + songStr);
	}
	
	bool isSongFinished() {
		return getTimeLeft() <= 0;
	}
	
	bool isWaitingToPlaySong() {
		return isSongFinished() and shouldWaitForListeners() > 0;
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
	
	int getTimeLeft() {
		if (queue.size() > 0) {
			int diff = int(TimeDifference(DateTime(), startTime).GetTimeDifference());
			int songLen = (queue[0].lengthMillis + 999) / 1000;
			return songLen - diff;
		}
		
		return 0;
	}
	
	Song@ getSong() {
		return queue.size() > 0 ? queue[0] : null;
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
		int queueSize = queue.size() > 0 ? (queue.size()-1) : 0;
		return queueColor + "(" + queueSize + " / " + g_maxQueue.GetInt() + ")";
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
	
	void handlePlayerLeave(CBasePlayer@ plr) {
		if (currentDj == getPlayerUniqueId(plr)) {
			currentDj = "";
			announce("" + plr.pev.netname + " tuned out and is not the DJ anymore.", HUD_PRINTTALK, plr);
		} else {
			announce("" + plr.pev.netname + " tuned out.", HUD_PRINTNOTIFY, plr);
		}
	}
	
	void playSong(Song@ song) {
		listenerCommand(song.getMp3PlayCommand());
		startTime = DateTime();
		
		array<CBasePlayer@> listeners = getChannelListeners();
		for (uint i = 0; i < listeners.size(); i++) {
			AmbientMusicRadio::toggleMapMusic(listeners[i], false);
		}
	}
	
	void stopMusic() {
		listenerCommand("mp3 stop");

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
		
		if (queue.size() == 0) {
			// play immediately since nothing else is playing/queued
			
			playSong(song);
			
			if (currentDj.Length() == 0) {
				announce("" + plr.pev.netname + " played: " + song.getName());
			} else {
				announce("Now playing: " + song.getName());
			}
			
			if (!autoDj)
				RelaySay(name + "|" + song.getName() + "|" + (getDj() !is null ? string(getDj().pev.netname) : "(none)"));
		} else {
			announce("" + plr.pev.netname + " queued: " + song.getName(), currentDj.Length() == 0 ? HUD_PRINTTALK : HUD_PRINTNOTIFY);
		}

		queue.insertLast(song);
		
		return true;
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