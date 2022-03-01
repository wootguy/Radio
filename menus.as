
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
		if (state.channel >= 0) {
			chan.handlePlayerLeave(plr, -1);
		}
		
		state.channel = -1;
		
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
	else if (option == "add-song") {
		g_Scheduler.SetTimeout("openMenuSong", 0.0f, EHandle(plr), "", 0, "");
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
			chan.announce("" + plr.pev.netname + " is now the DJ!");
		}
		state.lastDjToggle = g_Engine.time;
		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
	else if (option == "invite") {		
		g_Scheduler.SetTimeout("openMenuInvite", 0.0f, EHandle(plr));
	}
	else if (option == "help") {
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
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
		state.channel = atoi(option.SubString(chanPrefix.Length()));
		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
		
		if (oldChannel == state.channel) {
			return;
		}
		
		if (oldChannel >= 0) {
			g_channels[oldChannel].handlePlayerLeave(plr, state.channel);
		}
		
		bool musicIsPlaying = g_channels[state.channel].queue.size() > 0;

		clientCommand(plr, "stopsound");
		
		AmbientMusicRadio::toggleMapMusic(plr, !musicIsPlaying);
		
		g_channels[state.channel].announce("" + plr.pev.netname + " tuned in.", HUD_PRINTNOTIFY, plr);
	}
}

void callbackMenuSong(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];
	bool canDj = chan.canDj(plr);

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option.Find("search:") == 0) {
		string path = option.Length() > 7 ? option.SubString(7) : "";
		g_Scheduler.SetTimeout("openMenuSong", 0.0f, EHandle(plr), path, 0, "");
	}
	else if (option.Find("search-up:") == 0) {
		array<string> parts = option.Split(":");
		string childPath = parts[1];
		string path = parts[2];
		
		g_Scheduler.SetTimeout("openMenuSong", 0.0f, EHandle(plr), path, 0, childPath);
	}
	else if (option.Find("play:") == 0 or option.Find("playSearch:") == 0) {
		array<string> parts = option.Split(":");
		int page = atoi(parts[1]);
		string path = parts[2];
		string parentPath = getParentFolder(path);
		
		Song@ song = getNodeFromPath(path).file;
		
		if (!canDj)  {
			if (int(chan.queue.size()) >= g_maxQueue.GetInt()) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Can't request now. The queue is full.\n");
			}
			else if (!state.shouldRequestCooldown(plr)) {
				state.lastRequest = g_Engine.time;
				string helpPath = parentPath;
				if (helpPath.Length() > 0) {
					helpPath += "/";
				}
				chan.announce("" + plr.pev.netname + " requested: " + helpPath + song.getName());
				openMenuSongRequest(EHandle(chan.getDj()), plr.pev.netname, helpPath + song.getName(), path);
			}
		}
		else {			
			chan.queueSong(plr, song);
		}
		
		if (parts[0] == "playSearch") {
			g_Scheduler.SetTimeout("openMenuSearch", 0.0f, EHandle(plr), parts[3], page);
		}
		else if (page != -1) { // -1 = song was added by request - not by browsing
			g_Scheduler.SetTimeout("openMenuSong", 0.0f, EHandle(plr), parentPath, page, "");
		}
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
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
			chan.announce("" + plr.pev.netname + " moved up: " + chan.queue[slot].getName(), HUD_PRINTNOTIFY);
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
			chan.announce("" + plr.pev.netname + " moved down: " + chan.queue[slot].getName(), HUD_PRINTNOTIFY);
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
			chan.announce("" + plr.pev.netname + " removed: " + chan.queue[slot].getName(), msgType);
			chan.queue.removeAt(slot);
		}
		
		g_Scheduler.SetTimeout("openMenuEditQueue", 0.0f, EHandle(plr), -1);
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
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
		if (!canDj) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Only the DJ can stop videos.\n");
			g_Scheduler.SetTimeout("openMenuStopVideo", 0.0f, EHandle(plr));
			return;
		}
			
		if (state.shouldSongSkipCooldown(plr)) {
			g_Scheduler.SetTimeout("openMenuStopVideo", 0.0f, EHandle(plr));
			return;
		}
		
		if (chan.activeSongs.size() == 0) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] No videos are playing.\n");
			g_Scheduler.SetTimeout("openMenuStopVideo", 0.0f, EHandle(plr));
			return;
		}
		
		if (option.Find("stop-last") == 0 || option.Find("stop-first") == 0) {
			if (chan.activeSongs.size() < 2) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Only one video is playing.\n");
				g_Scheduler.SetTimeout("openMenuStopVideo", 0.0f, EHandle(plr));
				return;
			}
		}
		
		state.lastSongSkip = g_Engine.time;
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
			g_Scheduler.SetTimeout("openMenuInviteRequest", 0.5f, EHandle(target), "" + plr.pev.netname, state.channel);
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Invitation sent to " + target.pev.netname + "\n");
			
			state.lastInviteTime[targetId] = g_Engine.time;
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

void callbackMenuHelp(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option == "restart-music") {
		if (chan.queue.size() > 0) {
			Song@ song = chan.queue[0];
			clientCommand(plr, song.getMp3PlayCommand());
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Now playing: " + song.getName() + "\n");
		} else {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] There is no music playing on " + chan.name + "\n");
		}
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "download-pack") {
		g_Scheduler.SetTimeout("openMenuDownload", 0.0f, EHandle(plr));
	}
	else if (option == "help-commands") {
		showConsoleHelp(plr, true);
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "test-install") {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] You should be hearing a text-to-speech voice now. If not, increase music volume in Options -> Audio.\n");
		
		Song testSong = Song();
		testSong.path = g_version_check_file;
		
		clientCommand(plr, testSong.getMp3PlayCommand());
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "main-menu") {		
		g_Scheduler.SetTimeout("openMenuRadio", 0.0f, EHandle(plr));
	}
}

void callbackMenuDownload(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected()) {
		return;
	}

	PlayerState@ state = getPlayerState(plr);

	Channel@ chan = @g_channels[state.channel];

	string option = "";
	item.m_pUserData.retrieve(option);
	
	if (option.Find("download-") == 0) {
		int slot = atoi(option.SubString(9));
		
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Download link is below. You can copy it from the console. Extract to svencoop_downloads/\n\n");
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, g_music_packs[slot].link + "\n\n");
		
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
	else if (option == "help") {		
		g_Scheduler.SetTimeout("openMenuHelp", 0.0f, EHandle(plr));
	}
}



// Will show an "UPDATE NOW!!!!" sprite if the player doesn't have the latest version of the pack.
// When installing the new pack, the sprite file is overwritten with an invisble sprite.
void showUpdateSprite(EHandle h_plr, int stage) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	HUDSpriteParams params;
	params.channel = 0;
	params.spritename = "../" + g_root_path + g_version_check_spr;
	params.flags = HUD_SPR_MASKED | HUD_ELEM_ABSOLUTE_X | HUD_ELEM_SCR_CENTER_X;
	params.holdTime = 99999.0f;
	params.color1 = RGBA( 255, 255, 255, 255 );
	params.channel = 0;
	params.frame = 0;
	params.x = 0;
	params.y = 0.15;
	
	params.color2 = RGBA( 255, 0, 255, 255 );
	params.effect = HUD_EFFECT_COSINE;
	params.fxTime = 0.5f;
	params.holdTime = 6.5f;
	params.fadeoutTime = 0.5f;
	
	PlayerState@ state = getPlayerState(plr);	
	state.sawUpdateNotification = true;
	
	if (stage == 1) {
		g_PlayerFuncs.HudCustomSprite(plr, params);
		return;
	}
	
	if (stage == 0) {
		params.holdTime = 5.0f;
		params.fadeinTime = 0.5f;
		params.fadeoutTime = 0.5f;
		params.effect = 0;
		params.fxTime = 0;
		params.framerate = 15.0f;
		params.numframes = 255;
		params.frame = 1;
		
		params.channel = 1;
		params.x = 150;
		g_PlayerFuncs.HudCustomSprite(plr, params);
		
		params.channel = 2;
		params.x = -150;
		g_PlayerFuncs.HudCustomSprite(plr, params);
	
		g_Scheduler.SetTimeout("showUpdateSprite", 0.2f, h_plr, 1);
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

	g_menus[eidx].AddItem("\\wHelp\\y", any("help"));
	g_menus[eidx].AddItem("\\wTurn off\\y", any("turn-off"));
	g_menus[eidx].AddItem("\\wChange channel\\y", any("channels"));
	
	if (!chan.autoDj) {
		//g_menus[eidx].AddItem("\\w" + (canDj ? "Queue" : "Request") + " song" + "\\y", any("add-song"));
		g_menus[eidx].AddItem("\\w" + (canDj ? "Edit" : "View") + " queue  " + chan.getQueueCountString() + "\\y", any("edit-queue"));
		g_menus[eidx].AddItem("\\wStop video(s)\\y", any("stop-menu"));
		g_menus[eidx].AddItem((chan.spamMode ? "\\r" : "\\w") + (isDj ? "Quit DJ" : "Become DJ") + "\\y", any("become-dj"));
		g_menus[eidx].AddItem("\\wInvite\\y", any("invite"));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
	
	// Only show the update notification once per map, because it would be confusing
	// to see this sprite again after updating the pack (it won't be replaced until level change)
	if (!state.sawUpdateNotification) {
		g_Scheduler.SetTimeout("showUpdateSprite", 0.2f, h_plr, 0);
	}
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
		if (chan.autoDj) {
			djName = AUTO_DJ_NAME + " \\d(BOT)";
		}
		
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
			string label = "\\w" + chan.queue[i].getClippedName(48) + "\\y";
			
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
			string name = int(i) == selectedSlot ? chan.queue[i].getClippedName(120) : chan.queue[i].getClippedName(32);
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

void openMenuSong(EHandle h_plr, string path, int page, string lastChild) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	Channel@ chan = g_channels[state.channel];
	
	string prefix = "";
	if (path.Length() > 0) {
		prefix = path + "/";
	}
	
	string title = "Queue Song  " + chan.getQueueCountString();
	if (!chan.canDj(plr)) {
		title = "Request Song";
	}
	
	@g_menus[eidx] = CTextMenu(@callbackMenuSong);
	g_menus[eidx].SetTitle("\\y" + chan.name + " - " + title + "\\y\n/" + prefix + "    ");	
	
	FileNode@ node = getNodeFromPath(path);
	
	string upCommand = "main-menu";
	
	if (path != "") {
		string upDir = getParentFolder(path);
		upCommand = "search-up:" + node.name + ":" + upDir;
	}
	
	g_menus[eidx].AddItem("\\w..\\y", any(upCommand));
	
	bool moreThanOnePage = (node.children.size()+1) > 9;
	bool wentUp = lastChild.Length() > 0;
	
	for (uint i = 0; i < node.children.size(); i++) {
		FileNode@ child = node.children[i];
		
		if (moreThanOnePage and i != 0 && i % 6 == 0) {
			g_menus[eidx].AddItem("\\w..\\y", any(upCommand));
		}
		
		int itemPage = moreThanOnePage ? (i / 6) : 0;
		
		if (child.file !is null) {
			Song@ song = @child.file;			
			g_menus[eidx].AddItem(chan.getSongMenuLabel(song) + "\\y", any("play:" + itemPage + ":" + song.path));
		} else {
			if (wentUp and lastChild == child.name) {
				page = itemPage;
			}
			g_menus[eidx].AddItem("\\w" + child.name + "/\\y", any("search:" + prefix + child.name));
		}
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, page, plr);
}

void openMenuSearch(EHandle h_plr, string searchStr, int page) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	if (state.channel < 0) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] Join a channel before playing songs!\n");
		return;
	}
	Channel@ chan = g_channels[state.channel];
	
	if (chan.autoDj) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] " + AUTO_DJ_NAME + " doesn't take requests.\n");
		return;
	}
	
	@g_menus[eidx] = CTextMenu(@callbackMenuSong);
	
	string title = "Queue Song  " + chan.getQueueCountString();
	if (!chan.canDj(plr)) {
		title = "Request Song";
	}
	
	@g_menus[eidx] = CTextMenu(@callbackMenuSong);
	g_menus[eidx].SetTitle("\\y" + chan.name + " - " + title + "\\y\nResults for \"" + searchStr + "\"    ");	
	
	array<Song@> results = searchSongs(searchStr);
	
	if (results.size() == 0) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "[Radio] No results for \"" + searchStr + "\"\n");
		return;
	}
	
	bool moreThanOnePage = results.size() > 9;
	for (uint i = 0; i < results.size(); i++) {
		int itemPage = moreThanOnePage ? (i / 7) : 0;
		g_menus[eidx].AddItem("\\w" + chan.getSongMenuLabel(results[i]) + "\\y", any("playSearch:" + itemPage + ":" + results[i].path + ":" + searchStr));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, page, plr);
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
	
	g_menus[eidx].AddItem("\\wAccept\\y", any("channel-" + channel));
	
	string label = "\\wDecline\\y";
	label += "\n\nCurrent song:\n";
	
	label += chan.getCurrentSongString();
	
	g_menus[eidx].AddItem(label + "\\y", any("exit"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuSongRequest(EHandle h_plr, string asker, string songName, string songPath) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	
	@g_menus[eidx] = CTextMenu(@callbackMenuSong);
	g_menus[eidx].SetTitle("\\ySong request:\n" + songName + "\n-" + asker + "\n");
	
	g_menus[eidx].AddItem("\\wQueue song\\y", any("play:-1:" + songPath));	
	g_menus[eidx].AddItem("\\wIgnore\\y", any("exit"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
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
		
		g_menus[eidx].AddItem("\\w" + target.pev.netname + "\\y", any("invite-" + getPlayerUniqueId(target)));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuHelp(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	
	@g_menus[eidx] = CTextMenu(@callbackMenuHelp);
	g_menus[eidx].SetTitle("\\yRadio Help");
	
	g_menus[eidx].AddItem("\\w..\\y", any("main-menu"));
	g_menus[eidx].AddItem("\\rDownload music pack\\y", any("download-pack"));
	g_menus[eidx].AddItem("\\wTest installation\\y", any("test-install"));
	g_menus[eidx].AddItem("\\wRestart music\\y", any("restart-music"));
	//g_menus[eidx].AddItem("\\wShow command help\\y", any("help-commands"));
	
	string label = "\\wShow command help\\y";
	label += "\n\nMusic pack last updated:\n\\r" + g_music_pack_update_time + "\\y";
	
	g_menus[eidx].AddItem(label, any("help-commands"));
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void openMenuDownload(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}

	int eidx = plr.entindex();
	PlayerState@ state = getPlayerState(plr);
	
	@g_menus[eidx] = CTextMenu(@callbackMenuDownload);
	g_menus[eidx].SetTitle("\\yChoose Music Quality");
	g_menus[eidx].AddItem("\\w..\\y", any("help"));
	
	for (uint i = 0; i < g_music_packs.size(); i++) {		
		g_menus[eidx].AddItem("\\w" + g_music_packs[i].desc + "\\y", any("download-" + i));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

