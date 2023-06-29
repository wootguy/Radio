#include "Song.h"
#include "mmlib.h"

string Song::getClippedName(int length, bool ascii) {
	string name = getName(ascii);

	if (int(name.length()) > length) {
		int sz = (length - 4) / 2;
		return name.substr(0, sz) + " .. " + name.substr(name.length() - sz);
	}

	return name;
}

string Song::getName(bool ascii) {
	string name = artist + " - " + title;
	if (artist.length() == 0) {
		name = title.length() > 0 ? title : path;
	}

	if (!ascii) {
		return name;
	}

	string ascii_name = "";

	for (int i = 0; i < name.length(); i++) {
		if (name[i] >= 32 && name[i] <= 126) {
			ascii_name += name[i];
		}
	}

	if (ascii_name.length() == 0) {
		ascii_name = "?";
	}

	return ascii_name;
}

int Song::getTimeLeft() {
	int songLen = ((lengthMillis + 999) / 1000) - (offset / 1000);
	return songLen - getTimePassed();
}

int Song::getTimePassed() {
	if (loadState != SONG_LOADED) {
		startTime = g_engfuncs.pfnTime();
	}
	int diff = g_engfuncs.pfnTime() - startTime;
	return diff;
}

bool Song::isFinished() {
	return loadState == SONG_FAILED || (loadState == SONG_LOADED && getTimeLeft() <= 0 && lengthMillis != 0) || loadState == SONG_FINISHED;
}
