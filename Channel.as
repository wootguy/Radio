
class Channel {
	string name;
	int id = -1;
	array<Song@> queue;
	string currentDj; // steam id
	DateTime startTime; // time last song was started
	bool shouldSkipSong = false;
	int stopResumeHack = 0; // don't send "cd resume" commands during music transitions or else music fails to load
	
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
			shouldSkipSong = false;
			
			if (queue.size() > 0) {
				Song@ song = queue[0];
				print("Now playing: " + song.getName());
				playSong(song);
				RelaySay(name + "|" + song.getName() + "|" + (currentDj != "" ? string(getDj().pev.netname) : "(none)"));
			}
		}
		
		if (stopResumeHack > 0) {
			stopResumeHack -= 1;
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
	
	string getQueueCountString() {
		bool queueFull = int(queue.size()) > g_maxQueue.GetInt();
		string queueColor = queueFull ? "\\r" : "\\d";
		int queueSize = queue.size() > 0 ? (queue.size()-1) : 0;
		return queueColor + "(" + queueSize + " / " + g_maxQueue.GetInt() + ")";
	}
	
	CBasePlayer@ getDj() {
		return getPlayerByUniqueId(currentDj);
	}
	
	bool canDj(CBasePlayer@ plr) {
		CBasePlayer@ dj = getDj();
		return dj is null or dj.entindex() == plr.entindex();
	}
	
	void print(string msg, CBasePlayer@ exclude=null) {
		array<CBasePlayer@> listeners = getChannelListeners();
		
		for (uint i = 0; i < listeners.size(); i++) {
			if (exclude is null or (listeners[i].entindex() != exclude.entindex())) {
				g_PlayerFuncs.ClientPrint(listeners[i], HUD_PRINTTALK, "[Radio] " + msg + "\n");
			}
		}
	}
	
	void playSong(Song@ song) {	
		listenerCommand(song.getMp3PlayCommand());
		startTime = DateTime();
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
				print("" + plr.pev.netname + " played: " + song.getName());
			} else {
				print("Now playing: " + song.getName());
			}
			
			RelaySay(name + "|" + song.getName() + "|" + (currentDj != "" ? string(getDj().pev.netname) : "(none)"));
		} else {
			print("" + plr.pev.netname + " queued: " + song.getName());
		}

		stopResumeHack = 2;
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