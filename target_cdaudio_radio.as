// svencoop/media/tracklist.txt
array<string> g_audio_tracks = {
	"",
	"media/Half-Life01.mp3",
	"media/Half-Life02.mp3",
	"media/Half-Life03.mp3",
	"media/Half-Life04.mp3",
	"media/Half-Life05.mp3",
	"media/Half-Life06.mp3",
	"media/Half-Life07.mp3",
	"media/Half-Life08.mp3",
	"media/Half-Life09.mp3",
	"media/Half-Life10.mp3",
	"media/Half-Life11.mp3",
	"media/Half-Life12.mp3",
	"media/Half-Life13.mp3",
	"media/Half-Life14.mp3",
	"media/Half-Life15.mp3",
	"media/Half-Life16.mp3",
	"media/Half-Life17.mp3",
	"media/Half-Life18.mp3",
	"media/Half-Life19.mp3",
	"media/Half-Life20.mp3",
	"media/Half-Life21.mp3",
	"media/Half-Life22.mp3",
	"media/Half-Life23.mp3",
	"media/Half-Life24.mp3",
	"media/Half-Life25.mp3",
	"media/Half-Life26.mp3",
	"media/Half-Life27.mp3"
};

// duplicate of target_cdaudio except that it won't play music for players who are tuned into a radio channel
class target_cdaudio_radio : ScriptBaseEntity
{	
	void Use(CBaseEntity@ pActivator, CBaseEntity@ pCaller, USE_TYPE useType, float flValue = 0.0f)
	{
		int track = int(pev.health) - 1;
		
		string soundFile = "";
		if (track >= 0 and track < int(g_audio_tracks.size())) {
			soundFile = g_audio_tracks[track];
		}
		
		for ( int i = 1; i <= g_Engine.maxClients; i++ )
		{
			CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (plr is null or !plr.IsConnected()) {
				continue;
			}
			
			PlayerState@ state = getPlayerState(plr);
		
			if (state.channel >= 0 and g_channels[state.channel].queue.size() > 0) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] suppressed map music: " + soundFile + "\n");
				continue;
			}
			
			// using "mp3 <file>" because "cd #" is blocked by cl_filterstuffcmd
			if (track == -1) {
				clientCommand(plr, "mp3 stop");
			} else if (soundFile.Length() > 0) {
				clientCommand(plr, "mp3 play " + soundFile);
			}
		}
	}
};