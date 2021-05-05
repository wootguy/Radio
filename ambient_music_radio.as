#include "../SoundCache/StartSoundMsg"

namespace AmbientMusicRadio {

const int FL_START_SILENT = 1;
const int FL_LOOP = 2;
const int FL_ACTIVATOR_ONLY = 4;

void toggleMapMusic(CBasePlayer@ plr, bool toggleOn) {
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "ambient_music_radio"); 

		if (ent !is null)
		{
			ambient_music_radio@ music = cast<ambient_music_radio@>(CastToScriptClass(ent));
			if (toggleOn) {
				music.sync(plr);
			} else {
				music.stopSingleUser(plr);
			}
			
		}
	} while (ent !is null);
}

// duplicate of ambient_music except that it won't play music for players who are tuned into a radio channel
class ambient_music_radio : ScriptBaseEntity
{
	float startTime;
	bool isPlaying;
	
	void Spawn() {
		isPlaying = false;
		
		if (pev.spawnflags & FL_START_SILENT == 0) {
			play(null);
		}
	}
	
	void Use(CBaseEntity@ pActivator, CBaseEntity@ pCaller, USE_TYPE useType, float flValue = 0.0f) {		
		if (useType == USE_ON or (useType == USE_TOGGLE and !isPlaying)) {
			play(pActivator);
		} else {
			stop();
		}
	}
	
	void OnDestroy() {
		stop();
	}
	
	void play(CBaseEntity@ activator) {
		isPlaying = true;
		startTime = g_EngineFuncs.Time();
		
		if (pev.spawnflags & FL_ACTIVATOR_ONLY != 0) {
			if (activator !is null and activator.IsPlayer()) {
				playSingleUser(cast<CBasePlayer@>(activator));
			}
		}
		else {			
			for ( int i = 1; i <= g_Engine.maxClients; i++ )
			{
				CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
				
				if (plr is null or !plr.IsConnected()) {
					continue;
				}
				
				playSingleUser(plr);
			}
		}
	}
	
	void playSingleUser(CBasePlayer@ plr) {		
		PlayerState@ state = getPlayerState(cast<CBasePlayer@>(plr));
		
		if (state.isRadioListener()) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] suppressed map music: " + pev.message + "\n");
			return;
		}
		
		StartSoundMsgParams params;
		params.sample = pev.message;
		params.channel = CHAN_MUSIC;
		params.entindex = self.entindex();
		params.offset = g_EngineFuncs.Time() - startTime;
		params.flags = getSoundFlags();
		
		StartSoundMsg(params, MSG_ONE, plr.edict());
	}
	
	// play music at the current offset for a player that wasn't previously listening
	void sync(CBasePlayer@ target) {
		if (!isPlaying) {
			return;
		}
	
		playSingleUser(target);
	}
	
	bool isLooped() {
		string file = string(pev.message).ToLowercase();
		return (pev.spawnflags & FL_LOOP != 0) or int(file.Find("_loop.")) != -1;
	}
	
	int getSoundFlags() {
		return isLooped() ? SND_FORCE_LOOP : SoundFlag(0);
	}
	
	void stop() {
		isPlaying = false;
		g_SoundSystem.StopSound(self.edict(), CHAN_MUSIC, pev.message, false);
	}
	
	void stopSingleUser(CBasePlayer@ plr) {
		StartSoundMsgParams params;
		params.sample = pev.message;
		params.channel = CHAN_MUSIC;
		params.entindex = self.entindex();
		params.flags = SND_STOP;
		
		StartSoundMsg(params, MSG_ONE, plr.edict());
	}
}

}