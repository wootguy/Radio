
class Channel {
	string name;
	int id = -1;
	array<Song@> queue;
	string currentDj; // steam id
	DateTime startTime; // time last song was started
	string shouldSkipSong = ""; // name of player who skipped if not empty
	
	array<string> mapChangeListeners;
	
	void think() {
		if (shouldWaitForListeners() > 0) {
			return;
		}
		
		if (isSongFinished() or shouldSkipSong.Length() > 0) {
			if (queue.size() > 0) {
				queue.removeAt(0);
			}
			
			if (queue.size() > 0) {
				Song@ song = queue[0];
				string msg = "Now playing: " + song.getName();
				if (shouldSkipSong.Length() > 0) {
					if (currentDj.Length() == 0) {
						msg = "Song skipped by " + shouldSkipSong + ". " + msg;
					} else {
						msg = "Song skipped. " + msg;
					}
				}
				announce(msg);
				playSong(song);
				{
					CBasePlayer@ dj = getDj();
					RelaySay(name + "|" + song.getName() + "|" + (dj !is null ? string(getDj().pev.netname) : "(none)"));
				}
			} else if (shouldSkipSong.Length() > 0) {
				stopMusic();
				if (currentDj.Length() > 0) {
					announce("Song stopped by " + shouldSkipSong + ".");
				} else {
					announce("Song stopped.");
				}
			}
			
			shouldSkipSong = "";
		}
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