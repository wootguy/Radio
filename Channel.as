
class Channel {
	string name;
	int id = -1;
	array<Song@> queue;
	string currentDj; // steam id
	DateTime startTime; // time last song was started
	bool shouldSkipSong = false;
	
	void think() {
		bool isSongFinished = true;
		
		if (queue.size() > 0) {
			int timeleft = getTimeLeft();
			
			isSongFinished = timeleft <= 0;
			
			if (isSongFinished or shouldSkipSong) {
				queue.removeAt(0);
			}
		}
		
		if (isSongFinished or shouldSkipSong) {
			if (queue.size() > 0) {
				Song@ song = queue[0];
				string msg = "Now playing: " + song.getName();
				if (shouldSkipSong) {
					msg = "Song skipped. " + msg;
				}
				announce(msg);
				playSong(song);
				RelaySay(name + "|" + song.getName() + "|" + (currentDj != "" ? string(getDj().pev.netname) : "(none)"));
			} else if (shouldSkipSong) {
				stopMusic();
				announce("Song stopped.");
			}
			
			shouldSkipSong = false;
		}
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
	
	bool isDjReserved() {
		CBasePlayer@ dj = getDj();
		return dj is null and currentDj.Length() > 0 and g_Engine.time < g_djReserveTime.GetInt();
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
	}
	
	void stopMusic() {
		listenerCommand("mp3 stop");
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
			
			RelaySay(name + "|" + song.getName() + "|" + (currentDj != "" ? string(getDj().pev.netname) : "(none)"));
		} else {
			announce("" + plr.pev.netname + " queued: " + song.getName());
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