
void callbackMenuRadio(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	string option = "";
	item.m_pUserData.retrieve(option);
	
	bool canDj = true;
	Channel@ chan = null;
	if (state.channel >= 0) {
		canDj = g_channels[state.channel].canDj(plr);
		@chan = @g_channels[state.channel];
	}
	
	if (option == "channels") {
		g_Scheduler.SetTimeout("openMenuChannelSelect", 0.0f, EHandle(plr));
	}
	else if (option == "turn-off") {
		state.channel = -1;
		
		if (chan !is null) {
			chan.handlePlayerLeave(plr, -1);
		}
		
		string msg = "[Radio] Turned off.";
		if (state.neverUsedBefore) {
			state.neverUsedBefore = false;
			msg += " Say .radio to turn it back on.";
		}
		
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, msg + "\n");
		clientCommand(plr, "mp3 stop");
		
		HUDTextParams params;
		params.holdTime = 0.5f;
		params.x = -1;
		params.y = 0.0001;
		params.channel = 2;
		
		g_PlayerFuncs.HudMessage(plr, params, "");
		
		AmbientMusicRadio::toggleMapMusic(plr, true);
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "toggle-mute") {
		state.muteMode = (state.muteMode + 1) % MUTE_MODES;
		clientCommand(plr, "stopsound"); // switching too fast can cause stuttering
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "stop-menu") {
		if (chan.activeSongs.size() < 1) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] No videos are playing.\n");
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		if (!canDj) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Only the DJ can stop videos.\n");
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		g_Scheduler.SetTimeout("openMenuStopVideo", 0.0f, EHandle(plr));
	}
	else if (option == "edit-queue") {
		if (chan.queue.size() < 1) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] The queue is empty.\n");
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), -1);
	}
	else if (option == "become-dj") {
		CBasePlayer@ currentDj = chan.getDj();
		
		if (chan.isDjReserved()) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] DJ slot is reserved by someone who hasn't finished joining yet.\n");
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		if (chan.spamMode) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] The DJ feature is disabled in this channel.\n");
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		if (state.shouldDjToggleCooldown(plr)) {
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		if (currentDj !is null) {
			if (currentDj.entindex() != plr.entindex()) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] " + currentDj.pev.netname + " must stop DJ'ing first.\n");
			} else {
				chan.announce("" + currentDj.pev.netname + " is not the DJ anymore.\n");
				chan.currentDj = "";
			}
		}
		else {
			chan.currentDj = getPlayerUniqueId(plr);
			state.requestsAllowed = true;
			chan.emptyTime = g_EngineFuncs.Time(); // prevent immediate ejection
			chan.announce("" + plr.pev.netname + " is now the DJ!");
		}
		state.lastDjToggle = g_Engine.time;
		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "invite") {		
		g_Scheduler.SetTimeout("openMenuInvite", 0.0f, EHandle(plr));
	}
	else if (option == "hud") {
		state.showHud = !state.showHud;
		
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] HUD " + (state.showHud ? "enabled" : "disabled") + ".\n");
		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "help") {
		showConsoleHelp(plr, true);
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	} else {
		if (state.neverUsedBefore) {
			state.neverUsedBefore = false;
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Say .radio if you want to re-open the menu.\n");
		}
	}
}

void callbackMenuChannelSelect(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	string option = "";
	item.m_pUserData.retrieve(option);
	
	string chanPrefix = "channel-";

	if (option.Find(chanPrefix) == 0) {
		int oldChannel = state.channel;
		state.channel = atoi(option.SubString(chanPrefix.Length(), option.Find(":")));
		
		if (int(option.Find(":invited")) != -1) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] This menu is opened by saying .radio\n");
		}
		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
		
		if (oldChannel == state.channel) {
			return;
		}
		
		if (oldChannel >= 0) {
			g_channels[oldChannel].handlePlayerLeave(plr, state.channel);
		}
		
		bool musicIsPlaying = g_channels[state.channel].activeSongs.size() > 0;

		clientCommand(plr, "stopsound");
		
		AmbientMusicRadio::toggleMapMusic(plr, !musicIsPlaying);
		
		g_channels[state.channel].announce("" + plr.pev.netname + " tuned in.", HUD_PRINTNOTIFY, plr);
		updateSleepState();
	} else if (option.Find("block-request") == 0) {
		state.blockInvites = true;
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] You will no longer receive radio invites.\n");
	}
}

void callbackMenuRequest(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];
	bool canDj = chan.canDj(plr);

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option.Find("play-request") == 0) {
		array<string> parts = option.Split(":");
		int channelId = atoi(parts[1]);
		g_channels[channelId].announce("Request will be played now: " + g_channels[channelId].songRequest.title, HUD_PRINTCONSOLE);
		g_channels[channelId].songRequest.requester = plr.pev.netname;
		g_channels[channelId].playSong(g_channels[channelId].songRequest);
		g_channels[channelId].songRequest.id = 0;
		
		g_channels[channelId].lastSongRequest = 0;
		
	} else if (option.Find("queue-request") == 0) {
		array<string> parts = option.Split(":");
		int channelId = atoi(parts[1]);
		g_channels[channelId].songRequest.requester = plr.pev.netname;
		g_channels[channelId].queueSong(plr, g_channels[channelId].songRequest);
		g_channels[channelId].songRequest.id = 0;
		
		g_channels[channelId].lastSongRequest = 0;
		
	} else if (option.Find("deny-request") == 0) {
		array<string> parts = option.Split(":");
		int channelId = atoi(parts[1]);
		
		g_channels[channelId].songRequest.id = 0;
		g_channels[channelId].lastSongRequest = 0;
		g_channels[channelId].announce("" + plr.pev.netname + " denied the request.", HUD_PRINTNOTIFY);
	} else if (option.Find("block-request") == 0) {
		array<string> parts = option.Split(":");
		int channelId = atoi(parts[1]);
		
		state.requestsAllowed = false;
		g_channels[channelId].announce("" + plr.pev.netname + " is no longer taking requests.");
	}
}

void callbackMenuEditQueue(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];
	bool canDj = chan.canDj(plr);

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
		return;
	}
	
	if (!canDj) {
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), -1);
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Only the DJ can edit the queue.\n");
		return;
	}
	
	if (option.Find("edit-slot-") == 0) {
		int slot = atoi(option.SubString(10));
		
		if (!canDj) {
			slot = 0;
		}
		
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), slot);
	}
	else if (option.Find("move-up-") == 0) {
		int slot = atoi(option.SubString(8));
		int newSlot = slot;
		
		if (slot > 0) {
			chan.announce("" + plr.pev.netname + " moved up: " + chan.queue[slot].getName(false), HUD_PRINTNOTIFY);
			Song@ temp = chan.queue[slot];
			@chan.queue[slot] = @chan.queue[slot-1];
			@chan.queue[slot-1] = @temp;
			newSlot = slot-1;
		}
		
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), newSlot);
	}
	else if (option.Find("move-down-") == 0) {
		int slot = atoi(option.SubString(10));
		int newSlot = slot;
		
		if (slot < int(chan.queue.size())-1) {
			chan.announce("" + plr.pev.netname + " moved down: " + chan.queue[slot].getName(false), HUD_PRINTNOTIFY);
			Song@ temp = chan.queue[slot];
			@chan.queue[slot] = @chan.queue[slot+1];
			@chan.queue[slot+1] = @temp;
			newSlot = slot+1;
		}
		
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), newSlot);
	}
	else if (option.Find("remove-") == 0) {
		int slot = atoi(option.SubString(7));
		
		if (slot < int(chan.queue.size())) {
			HUD msgType = chan.hasDj() ? HUD_PRINTNOTIFY : HUD_PRINTTALK;
			chan.announce("" + plr.pev.netname + " removed: " + chan.queue[slot].getName(false), msgType);
			chan.queue.removeAt(slot);
		}
		
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), -1);
	}
	else if (option == "edit-queue") {
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), -1);
	}
}

void callbackMenuStopVideo(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];
	bool canDj = chan.canDj(plr);

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option.Find("main-menu") == 0) {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	
	if (option.Find("stop-") == 0) {
		g_Scheduler.SetTimeout("openMenuStopVideo", 0.0f, EHandle(plr));
		
		if (option.Find("stop-all") == 0) {		
			chan.stopMusic(plr, -1, false);
		} else if (option.Find("stop-last") == 0) {
			chan.stopMusic(plr, 0, false);
		} else if (option.Find("stop-first") == 0) {
			chan.stopMusic(plr, chan.activeSongs.size()-1, false);
		} else if (option.Find("stop-and-clear-queue") == 0) {
			chan.stopMusic(plr, -1, true);
		}
	}
}

void callbackMenuInvite(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option == "inviteall") {
		int inviteCount = 0;
	
		if (state.shouldInviteCooldown(plr, "\\everyone")) {
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
	
		for ( int i = 1; i <= g_Engine.maxClients; i++ )
		{
			CBasePlayer@ target = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (target is null or !target.IsConnected() or plr.entindex() == target.entindex()) {
				continue;
			}
			PlayerState@ targetState = getPlayerState(target);
			
			if (targetState.channel == state.channel) {
				continue;
			}
			if (targetState.blockInvites) {
				g_PlayerFuncs.ClientPrint(target, HUD_PRINTNOTIFY, "[Radio] Blocked invite from " + plr.pev.netname + "\n");
				continue;
			}
			
			g_Scheduler.SetTimeout("openMenuInviteRequest", 0.5f, EHandle(target), "" + plr.pev.netname, state.channel);
			inviteCount++;
		}
		
		if (inviteCount == 0) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] No one to invite.\n");
		}
		else {
			state.lastInviteTime["\\everyone"] = g_Engine.time;
			chan.announce("" + plr.pev.netname + " invited " + inviteCount + " players");
		}

		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option.Find("invite-") == 0) {
		string targetId = option.SubString(7);
		CBasePlayer@ target = getPlayerByUniqueId(targetId);
		
		if (state.shouldInviteCooldown(plr, targetId)) {
			g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
			return;
		}
		
		if (target !is null) {
			PlayerState@ targetState = getPlayerState(target);
			
			if (!targetState.blockInvites) {
				g_Scheduler.SetTimeout("openMenuInviteRequest", 0.5f, EHandle(target), "" + plr.pev.netname, state.channel);
			
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Invitation sent to " + target.pev.netname + "\n");
				
				state.lastInviteTime[targetId] = g_Engine.time;
			} else {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] " + target.pev.netname + " has blocked invites.\n");
			}
		} else {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Invitation failed. Player left the game.\n");
		}
		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option.Find("invite-decline-") == 0) {
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
}



void openMenuRadio(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);	
	Channel@ chan = g_channels[state.channel];
	
	@g_menus[eidx] = CTextMenu(@callbackMenuRadio);
	g_menus[eidx].SetTitle("\\yRadio - " + chan.name);

	CBasePlayer@ dj = chan.getDj();
	bool isDjReserved = chan.isDjReserved();
	bool canDj = chan.canDj(plr);
	bool isDj = dj !is null and dj.entindex() == plr.entindex();
	
	string muted = "\\d(off)";
	if (state.muteMode == MUTE_TTS) {
		muted = "speech";
	} else if (state.muteMode == MUTE_VIDEOS) {
		muted = "videos";
	}
	
	

	g_menus[eidx].AddItem("\\wHelp\\y", any("help"));
	g_menus[eidx].AddItem("\\wTurn off\\y", any("turn-off"));
	g_menus[eidx].AddItem("\\wChange channel\\y", any("channels"));
	g_menus[eidx].AddItem("\\w" + (canDj ? "Edit" : "View") + " queue  " + chan.getQueueCountString() + "\\y", any("edit-queue"));
	g_menus[eidx].AddItem("\\wStop video(s)\\y", any("stop-menu"));
	g_menus[eidx].AddItem("\\wHUD: " + (state.showHud ? "on" : "off") + "\\y", any("hud"));
	g_menus[eidx].AddItem("\\wMute: " + muted + "\\y", any("toggle-mute"));
	g_menus[eidx].AddItem((chan.spamMode ? "\\d" : "\\w") + (isDj ? "Quit DJ" : "Become DJ") + "\\y", any("become-dj"));
	g_menus[eidx].AddItem("\\wInvite\\y", any("invite"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuStopVideo(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);	
	Channel@ chan = g_channels[state.channel];
	
	@g_menus[eidx] = CTextMenu(@callbackMenuStopVideo);
	g_menus[eidx].SetTitle("\\y" + chan.name + " - Stop video(s)");

	CBasePlayer@ dj = chan.getDj();
	bool isDjReserved = chan.isDjReserved();
	bool canDj = chan.canDj(plr);
	bool isDj = dj !is null and dj.entindex() == plr.entindex();

	g_menus[eidx].AddItem("\\w..\\y", any("main-menu"));
	g_menus[eidx].AddItem("\\wStop all videos\\y", any("stop-all"));
	g_menus[eidx].AddItem("\\wStop all videos except the first\\y", any("stop-last"));
	g_menus[eidx].AddItem("\\wStop all videos except the last\\y", any("stop-first"));
	g_menus[eidx].AddItem("\\wStop all videos and clear the queue\\y", any("stop-and-clear-queue"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuChannelSelect(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	
	@g_menus[eidx] = CTextMenu(@callbackMenuChannelSelect);
	g_menus[eidx].SetTitle("\\yRadio Channels\n");
	
	for (uint i = 0; i < g_channels.size(); i++) {
		Channel@ chan = g_channels[i];
		string label = "\\w" + chan.name;
		
		array<CBasePlayer@> listeners = chan.getChannelListeners();
		
		CBasePlayer@ dj = chan.getDj();
		
		if (listeners.size() > 0) {			
			label += "\\d  (" + listeners.size() + " listening)";
		}
		
		string djName = dj !is null ? string(dj.pev.netname) : "\\d(none)";
		
		label += "\n\\y      Current DJ:\\w " + (chan.spamMode ? "\\d(disabled)" : djName);
		label += "\n\\y      Now Playing:\\w " + chan.getCurrentSongString();
		
		label += "\n\\y";
		
		g_menus[eidx].AddItem(label, any("channel-" + i));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuEditQueue(EHandle h_plr, int selectedSlot) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[state.channel];
	
	string title = chan.canDj(plr) ? "Edit queue" : "View queue";
	
	@g_menus[eidx] = CTextMenu(@callbackMenuEditQueue);
	
	if (selectedSlot == -1) {
		g_menus[eidx].SetTitle("\\y" + chan.name + " - " + title);
		g_menus[eidx].AddItem("\\w..\\y", any("main-menu"));
		
		for (uint i = 0; i < chan.queue.size(); i++) {
			string label = "\\w" + chan.queue[i].getClippedName(48, true) + "\\y";
			
			// try to keep the menu spacing the same in both edit modes
			if (i == chan.queue.size()-1) {
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
			
			g_menus[eidx].AddItem(label, any("edit-slot-" + i));
		}
	} else {
		string label = "\\y" + chan.name + " - " + title + "\n";
		
		for (uint i = 0; i < chan.queue.size(); i++) {
			string color = int(i) == selectedSlot ? "\\r" : "\\w";
			string name = int(i) == selectedSlot ? chan.queue[i].getClippedName(120, true) : chan.queue[i].getClippedName(32, true);
			label += "\n" + color + "    " + name + "\\y";
		}
		
		label += "\n\n\\yAction:";
		
		g_menus[eidx].SetTitle(label);
		g_menus[eidx].AddItem("\\wCancel\\y", any("edit-queue"));
		g_menus[eidx].AddItem("\\wMove up\\y", any("move-up-" + selectedSlot));
		g_menus[eidx].AddItem("\\wMove down\\y", any("move-down-" + selectedSlot));
		g_menus[eidx].AddItem("\\wRemove\\y", any("remove-" + selectedSlot));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuInviteRequest(EHandle h_plr, string asker, int channel) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[channel];
	
	@g_menus[eidx] = CTextMenu(@callbackMenuChannelSelect);
	g_menus[eidx].SetTitle("\\yYou're invited to listen to\nthe radio on " + g_channels[channel].name + "\n-" + asker + "\n");
	
	g_menus[eidx].AddItem("\\wAccept\\y", any("channel-" + channel + ":invited"));
	g_menus[eidx].AddItem("\\wIgnore\\y", any("exit"));
	
	string label = "\\wBlock invites\\y";
	label += "\n\nNow playing:\n";
	
	label += chan.getCurrentSongString();
	
	g_menus[eidx].AddItem(label + "\\y", any("block-requests"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuSongRequest(EHandle h_plr, string asker, string songName, int channelId) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	
	@g_menus[eidx] = CTextMenu(@callbackMenuRequest);
	g_menus[eidx].SetTitle("\\yRadio request from \"" + asker + "\":\n\n" + songName + "\n");
	
	g_menus[eidx].AddItem("\\wPlay now\\y", any("play-request:" + channelId));
	g_menus[eidx].AddItem("\\wAdd to queue\\y", any("queue-request:" + channelId));
	g_menus[eidx].AddItem("\\wDeny request\\y", any("deny-request:" + channelId));
	g_menus[eidx].AddItem("\\wDisable requests\\y", any("block-request:" + channelId));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(SONG_REQUEST_TIMEOUT, 0, plr);
}

void openMenuInvite(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[state.channel];
	
	@g_menus[eidx] = CTextMenu(@callbackMenuInvite);
	g_menus[eidx].SetTitle("\\y" + chan.name + " - Invite");
	
	g_menus[eidx].AddItem("\\w..\\y", any("main-menu"));
	g_menus[eidx].AddItem("\\rEveryone\\y", any("inviteall"));
	
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ target = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (target is null or !target.IsConnected() or plr.entindex() == target.entindex()) {
			continue;
		}
		
		PlayerState@ targetState = getPlayerState(target);
		if (targetState.channel == state.channel) {
			continue;
		}
		string color = targetState.blockInvites ? "\\d" : "\\w";
		
		g_menus[eidx].AddItem(color + target.pev.netname + "\\y", any("invite-" + getPlayerUniqueId(target)));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

