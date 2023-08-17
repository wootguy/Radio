#include <radio_utils.h>

enum SONG_LOAD_STATES {
	SONG_UNLOADED,
	SONG_LOADING,
	SONG_LOADED,
	SONG_FAILED,
	SONG_FINISHED // needed for videos that have no duration info
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