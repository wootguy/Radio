#include "meta_utils.h"
#include "radio_utils.h"
#include "FakeMic.h"
#include "Song.h"

struct PacketListener {
	uint32_t packetId; // packet id that indicates a song has started
	uint32_t songId; // song that was started
};

struct Channel {
	string name;
	int id = -1;
	int maxStreams = 4; // max videso that can be played at the same time
	vector<Song> queue;
	vector<Song> activeSongs; // songs playing at the same time
	string currentDj; // steam id

	bool spamMode = false; // no DJs allowed. spammers and stoppers fight to the death
	vector<Song> songsLeft; // songs left to play in auto dj queue

	float emptyTime = 0; // time the channel became inactive
	bool wasEmpty = false; // true if the channel was doing nothing last update

	float lastSongRequest = 0;
	Song songRequest; // song to be requested
	string requester;

	Channel() {}
	Channel(const Channel& channel) {};

	vector<PacketListener> packetListeners;
	ThreadSafeQueue<VoicePacket> packetStream;

	void think();
	void rename(edict_t* namer, string newName);
	void updateHud(edict_t* plr, PlayerState& state);
	string getCurrentSongString();
	bool areSongsFinished();
	void triggerPacketEvents(uint32_t packetId);
	string getQueueCountString();
	edict_t* getDj();
	bool hasDj();
	bool isDjReserved();
	bool canDj(edict_t* plr);
	bool requestSong(edict_t* plr, Song song);
	void announce(string msg, int messageType = HUD_PRINTTALK, edict_t* exclude = NULL);
	void advertise(string msg, int messageType = HUD_PRINTNOTIFY);
	void handlePlayerLeave(edict_t* plr, int newChannel);
	void playSong(Song song);
	void cancelSong(uint32_t songId, string reason);
	void finishSong(uint32_t songId);
	void stopMusic(edict_t* skipper, int excludeIdx, bool clearQueue);
	bool queueSong(edict_t* plr, Song song);
	Song* findSongById(uint32_t songId);
	void updateSongInfo(uint32_t songId, string title, int duration, int offset);
	vector<edict_t*> getChannelListeners(bool excludeVideoMuters = false);
	void listenerCommand(string cmd);
};