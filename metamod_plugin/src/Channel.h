#include "meta_utils.h"
#include "radio_utils.h"
#include "FakeMic.h"

struct PacketListener {
	uint32_t packetId; // packet id that indicates a song has started
	uint32_t songId; // song that was started
};

struct Song {
	string title;
	string artist;
	string path; // file path or youtube url
	uint32_t lengthMillis; // duration in milliseconds

	int offset;
	int loadState = SONG_LOADED;
	uint32_t id = 0; // used to relate messages from the voice server to a song in some channel's queue
	string requester;
	float startTime;
	bool isPlaying = false;
	bool messageSent = false; // was chat message sent about this song being added
	bool noRestart = false; // failsafe for infinite video restarting
	string args; // playback args (time offset)
	float loadTime; // time that song started waiting to start after loading

	Song() {}
	Song(const Song& other);

	string getClippedName(int length, bool ascii);
	string getName(bool ascii);
	int getTimeLeft();
	int getTimePassed();
	bool isFinished();
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

	vector<PacketListener> packetListeners;
	vector<VoicePacket> packetStream;

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