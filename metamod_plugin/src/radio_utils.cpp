#include "radio_utils.h"
#include "radio.h"

map<string, uint64_t> g_sound_durations;

typedef struct WAV_HEADER {
	/* RIFF Chunk Descriptor */
	uint8_t RIFF[4] = { 'R', 'I', 'F', 'F' }; // RIFF Header Magic header
	uint32_t ChunkSize;                     // RIFF Chunk Size
	uint8_t WAVE[4] = { 'W', 'A', 'V', 'E' }; // WAVE Header
	/* "fmt" sub-chunk */
	uint8_t fmt[4] = { 'f', 'm', 't', ' ' }; // FMT header
	uint32_t Subchunk1Size = 16;           // Size of the fmt chunk
	uint16_t AudioFormat = 1; // Audio format 1=PCM,6=mulaw,7=alaw,     257=IBM
								// Mu-Law, 258=IBM A-Law, 259=ADPCM
	uint16_t NumOfChan = 1;   // Number of channels 1=Mono 2=Sterio
	uint32_t SamplesPerSec = 12000;   // Sampling Frequency in Hz
	uint32_t bytesPerSec = 12000 * 2; // bytes per second
	uint16_t blockAlign = 2;          // 2=16-bit mono, 4=16-bit stereo
	uint16_t bitsPerSample = 16;      // Number of bits per sample
	/* "data" sub-chunk */
	uint8_t Subchunk2ID[4] = { 'd', 'a', 't', 'a' }; // "data"  string
	uint32_t Subchunk2Size;                        // Sampled data length
} wav_hdr;

uint64_t getSoundDuration(string fpath) {
	if (g_sound_durations.find(fpath) != g_sound_durations.end()) {
		return g_sound_durations[fpath];
	}

	uint64_t duration = 0;

	string ext = toLowerCase(getFileExtension(fpath));

	FILE* file = fopen((string("svencoop_addon/sound/") + fpath).c_str(), "rb");

	if (!file) {
		file = fopen((string("svencoop/sound/") + fpath).c_str(), "rb");
	}
	if (!file) {
		file = fopen((string("svencoop_downloads/sound/") + fpath).c_str(), "rb");
	}

	if (!file) {
		println("[Radio] Failed to check file duration: %s", fpath.c_str());
	}
	else if(ext == "wav") {
		WAV_HEADER header;
		if (fread(&header, sizeof(WAV_HEADER), 1, file) == 1) {
			int numSamples = header.Subchunk2Size / (header.NumOfChan * (header.bitsPerSample / 8));
			duration = numSamples / (header.SamplesPerSec / 1000);
		}
	}
	else {
		println("[Radio] Don't know how to check duration of %s file", ext.c_str());
	}

	if (file)
		fclose(file);

	g_sound_durations[fpath] = duration;
	return duration;
}

string getFileExtension(string fpath) {
	int dot = fpath.find_last_of(".");
	if (dot != -1 && dot < fpath.size()-1) {
		return fpath.substr(dot + 1);
	}

	return "";
}

PlayerState& getPlayerState(edict_t* plr) {
	string steamId = getPlayerUniqueId(plr);

	if (g_player_states.find(steamId) == g_player_states.end()) {
		PlayerState* newState = new PlayerState();
		g_player_states[steamId] = newState;
	}
	
	return *g_player_states[steamId];
}

string getPlayerUniqueId(edict_t* plr) {
	if (plr == NULL) {
		return "STEAM_ID_NULL";
	}

	string steamId = (*g_engfuncs.pfnGetPlayerAuthId)(plr);

	if (steamId == "STEAM_ID_LAN" || steamId == "BOT") {
		steamId = STRING(plr->v.netname);
	}

	return steamId;
}

string replaceString(string subject, string search, string replace)
{
	size_t pos = 0;
	while ((pos = subject.find(search, pos)) != string::npos)
	{
		subject.replace(pos, search.length(), replace);
		pos += replace.length();
	}
	return subject;
}

edict_t* getPlayerByUniqueId(string id) {
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);

		if (!ent || (ent->v.flags & FL_CLIENT) == 0) {
			continue;
		}

		if (id == getPlayerUniqueId(ent)) {
			return ent;
		}
	}

	return NULL;
}

edict_t* getPlayerByUserId(int id) {
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);

		if (!isValidPlayer(ent)) {
			continue;
		}

		if (id == (*g_engfuncs.pfnGetPlayerUserId)(ent)) {
			return ent;
		}
	}

	return NULL;
}

bool isValidPlayer(edict_t* plr) {
	return plr && (plr->v.flags & FL_CLIENT) != 0;
}

void clientCommand(edict_t* plr, string cmd, int destType) {
	MESSAGE_BEGIN(destType, 9, NULL, plr);
	WRITE_STRING(UTIL_VarArgs(";%s;", cmd.c_str()));
	MESSAGE_END();
}

string trimSpaces(string s)
{
	// Remove white space indents
	int lineStart = s.find_first_not_of(" \t\n\r");
	if (lineStart == string::npos)
		return "";

	// Remove spaces after the last character
	int lineEnd = s.find_last_not_of(" \t\n\r");
	if (lineEnd != string::npos && lineEnd < s.length() - 1)
		s = s.substr(lineStart, (lineEnd + 1) - lineStart);
	else
		s = s.substr(lineStart);

	return s;
}

bool cgetline(FILE* file, string& output) {
	static char buffer[4096];

	if (fgets(buffer, sizeof(buffer), file)) {
		output = string(buffer);
		if (output[output.length() - 1] == '\n') {
			output = output.substr(0, output.length() - 1);
		}
		return true;
	}

	return false;
}

string formatTime(int totalSeconds) {
	int hours = totalSeconds / (60 * 60);
	int minutes = (totalSeconds / 60) - hours * 60;
	int seconds = totalSeconds % 60;

	if (hours > 0) {
		return UTIL_VarArgs("%d:%02d:%02d", hours, minutes, seconds);
	}
	else {
		return UTIL_VarArgs("%d:%02d", minutes, seconds);
	}
}

vector<string> splitString(string str, const char* delimitters)
{
	vector<string> split;
	if (str.size() == 0)
		return split;

	// somehow plain assignment doesn't create a copy and even modifies the parameter that was passed by value (WTF!?!)
	//string copy = str; 
	string copy;
	for (int i = 0; i < str.length(); i++)
		copy += str[i];

	char* tok = strtok((char*)copy.c_str(), delimitters);

	while (tok != NULL)
	{
		split.push_back(tok);
		tok = strtok(NULL, delimitters);
	}
	return split;
}

uint32_t getFileSize(FILE* file) {
	fseek(file, 0, SEEK_END); // seek to end of file
	uint32_t size = ftell(file); // get current file pointer
	fseek(file, 0, SEEK_SET);
	return size;
}

float clampf(float val, float min, float max) {
	if (val > max) {
		return max;
	}
	else if (val < min) {
		return min;
	}
	return val;
}

int clamp(int val, int min, int max) {
	if (val > max) {
		return max;
	}
	else if (val < min) {
		return min;
	}
	return val;
}

void setKeyValue(edict_t* ent, char* key, char* value) {
	KeyValueData dat;
	dat.fHandled = false;
	dat.szClassName = (char*)STRING(ent->v.classname);
	dat.szKeyName = key;
	dat.szValue = value;
	gpGamedllFuncs->dllapi_table->pfnKeyValue(ent, &dat);
}

// send a message the angelscript chat bridge plugin
void RelaySay(string message) {
	std::remove(message.begin(), message.end(), '\n'); // stip any newlines, ChatBridge.as takes care
	replaceString(message, "\"", "'"); // replace quotes so cvar is set correctly

	logln(string("[RelaySay ") + Plugin_info.name + "]: " + message + "\n");
	
	g_engfuncs.pfnCVarSetString("relay_say_msg", message.c_str());
	g_engfuncs.pfnServerCommand(UTIL_VarArgs("as_command .relay_say %s\n", Plugin_info.name));
	g_engfuncs.pfnServerExecute();
}