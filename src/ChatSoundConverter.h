#include <map>
#include <vector>
#include <string>
#include <fstream>
#include "SteamVoiceEncoder.h"

class ConvertJob {
public:
	int16_t* samples; // samples ready to be converted
	int numSamples;
	std::ofstream* outFile;
	SteamVoiceEncoder* encoder;
	int offset; // encode 

	ConvertJob(int16_t* samples, int numSamples, std::ofstream* outFile, SteamVoiceEncoder* encoder);
	~ConvertJob();
};

class ChatSoundConverter {
public:
	ChatSoundConverter(std::string commandFilePath, std::string chatsoundCfgPath, std::string svenRootPath);

	// poll for and execute commands forever
	int pollCommands();

private:
	int sampleRate;
	int frameDuration;
	int frameSize;
	int framesPerPacket;
	int packetDelay;
	int samplesPerPacket;
	int opusBitrate;

	std::string commandFilePath;
	std::string chatsoundCfgPath;
	std::string svenRootPath;

	// maps a chatsound trigger to raw PCM data (mono)
	std::map<std::string, std::vector<int8_t>> chatsounds_to_pcm;
	std::vector<ConvertJob*> jobs;

	// loads all chatsounds into memory for faster conversions
	void loadChatsounds();

	bool loadChatsound(std::string trigger, std::string fpath);

	ConvertJob* createConvertJob(std::string trigger, int pitch, int steamid);

	bool convert(ConvertJob* job);
};