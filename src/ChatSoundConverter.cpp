#include "ChatSoundConverter.h"
#include "util.h"
#include <chrono>
#include <thread>
#include <string.h>

using namespace std;

static uint64_t steam_min = 0x0110000100000001;
static uint64_t steam_max = 0x01100001FFFFFFFF;

ChatSoundConverter::ChatSoundConverter(string commandFilePath, string chatsoundCfgPath, string svenRootPath) {
	this->commandFilePath = commandFilePath;
	this->chatsoundCfgPath = chatsoundCfgPath;
	this->svenRootPath = svenRootPath;

	sampleRate = 12000; // opus allows: 8, 12, 16, 24, 48 khz
	frameDuration = 10; // opus allows: 2.5, 5, 10, 20, 40, 60, 80, 100, 120
	frameSize = (sampleRate / 1000) * frameDuration; // samples per frame
	framesPerPacket = 5; // 2 = minimum amount of frames for sven to accept packet
	packetDelay = frameDuration * framesPerPacket; // millesconds between output packets
	samplesPerPacket = frameSize * framesPerPacket;
	opusBitrate = 32000; // 32khz = steam default
}

uint64_t steamid_to_steamid64(string steamid) {
	uint64_t X = atoi(steamid.substr(8, 1).c_str());
	uint64_t Y = atoi(steamid.substr(10).c_str());

	uint64_t steam64id = 76561197960265728;
	steam64id += Y * 2;
	if (X == 1) {
		steam64id += 1;
	}
	
	return steam64id;
}

int ChatSoundConverter::pollCommands() {
	loadChatsounds();

	printf("Command file: %s\n", commandFilePath.c_str());

	ifstream ifs(commandFilePath);

	if (ifs.is_open())
	{
		ifs.seekg(0, ios_base::end);

		string line;
		while (true)
		{
			while (getline(ifs, line)) {
				if (line == "!RELOAD_SOUNDS") {
					loadChatsounds();
					continue;
				}
				vector<string> parts = splitString(line, " ");

				if (parts.size() < 5) {
					continue;
				}

				string trigger = parts[0];
				int pitch = atoi(parts[1].c_str());
				int volume = atoi(parts[2].c_str());
				int id = atoi(parts[3].c_str());
				uint64_t steamid64 = steamid_to_steamid64(parts[4]);

				printf("%s %d %d %d %llu\n", trigger.c_str(), pitch, volume, id, steamid64);

				ConvertJob* job = createConvertJob(trigger, pitch, volume, id, steamid64);

				if (job) {
					jobs.push_back(job);
				}
			}
			if (!ifs.eof())
				break; // Ensure end of read was EOF.
			ifs.clear();

			if (jobs.size()) {
				vector<ConvertJob*> newJobs;

				for (int i = 0; i < jobs.size(); i++) {
					if (!convert(jobs[i])) {
						newJobs.push_back(jobs[i]);
					}
					else {
						delete jobs[i];
						//printf("Finished convert job\n");
					}
				}

				jobs = newJobs;
			}
			else {
				// TODO: use windows/linux file change notifations instead of this
				std::this_thread::sleep_for(std::chrono::milliseconds(10));
			}
		}
	}

	return 0;
}

void ChatSoundConverter::loadChatsounds() {
	chatsounds_to_pcm.clear();

	ifstream file(chatsoundCfgPath);

	vector<string> search_paths = {
		svenRootPath + "/svencoop_addon/sound/",
		svenRootPath + "/svencoop/sound/",
		svenRootPath + "/svencoop_downloads/sound/",
	};

	printf("\nLoading chatsounds...\n");

	if (file.is_open())
	{
		string line;
		while (getline(file, line)) {
			if (line.length() == 0 || line.find("//") == 0 || line.find("[extra_sounds]") == 0) {
				continue;
			}

			vector<string> parts = splitString(line, " \t");
			if (parts.size() < 2) {
				continue;
			}
			string trigger = parts[0];
			string relPath = parts[1];

			string fpath;

			for (int i = 0; i < search_paths.size(); i++) {
				string testPath = search_paths[i] + relPath;
				if (fileExists(testPath)) {
					fpath = testPath;
					break;
				}
			}
			
			if (fpath.size() == 0) {
				printf("Failed to find chatsound: %s\n", relPath.c_str());
				continue;
			}

			//printf("GOT CSOUNMD: %s = %s\n", trigger.c_str(), fpath.c_str());
			loadChatsound(trigger, fpath);
		}

		// TODO: use windows/linux file change notifations instead of this
		std::this_thread::sleep_for(std::chrono::milliseconds(10));
	}

	int total = 0;
	for (auto const& x : chatsounds_to_pcm) {
		total += x.second.size();
	}

	printf("Loaded %.2f MB of audio data into memory\n", (float)total / (1024.0f*1024.0f));
}

bool ChatSoundConverter::loadChatsound(string trigger, string inputPath) {
	ifstream inputFile(inputPath, ios::binary);
	wav_hdr header;

	inputFile.read((char*)&header, sizeof(header));

	if (header.RIFF[0] != 'R' || header.RIFF[1] != 'I' || header.RIFF[2] != 'F' || header.RIFF[3] != 'F') {
		fprintf(stderr, "ERROR: Invalid WAV file\n");
		return false;
	}

	int numSamples = header.ChunkSize - (sizeof(wav_hdr) - 8);

	int16_t* newSamples;

	if (header.bitsPerSample == 8) {
		uint8_t* samples = new uint8_t[numSamples];
		inputFile.read((char*)samples, numSamples);
		inputFile.close();

		// convert 8bit to 16bit
		newSamples = new int16_t[numSamples];
		for (int i = 0; i < numSamples; i++) {
			newSamples[i] = ((int16_t)samples[i] - 128) * 256;
		}

		delete[] samples;
	}
	else if (header.bitsPerSample == 16) {
		newSamples = new int16_t[numSamples];
		inputFile.read((char*)newSamples, numSamples * sizeof(int16_t));
		inputFile.close();
	}
	else {
		fprintf(stderr, "ERROR: Expected 8 or 16 bit samples\n");
		return false;
	}

	if (header.NumOfChan == 2) {
		numSamples = mixStereoToMono(newSamples, numSamples);
	}
	else if (header.NumOfChan != 1) {
		fprintf(stderr, "ERROR: Unexpected channel count %d\n", header.NumOfChan);
		return false;
	}

	if (header.SamplesPerSec != sampleRate) {
		//fprintf(stderr, "Resampling %d to %d\n", header.SamplesPerSec, sampleRate);

		float* floatSamples = new float[numSamples];
		for (int i = 0; i < numSamples; i++) {
			floatSamples[i] = (float)newSamples[i] / 32768.0f;
		}

		vector<float> resampled = sample_rate_convert(floatSamples, numSamples, header.SamplesPerSec, sampleRate);
		delete[] floatSamples;

		delete[] newSamples;
		numSamples = resampled.size();
		newSamples = new int16_t[numSamples];

		for (int i = 0; i < numSamples; i++) {
			newSamples[i] = clampf(resampled[i], -1.0f, 1.0f) * 31767.0f;
		}
	}

	vector<int8_t> memSamples;
	memSamples.reserve(numSamples);

	for (int i = 0; i < numSamples; i++) {
		memSamples.push_back(newSamples[i] >> 8);
	}

	chatsounds_to_pcm[trigger] = memSamples;

	delete[] newSamples;

	return true;
}

ConvertJob* ChatSoundConverter::createConvertJob(string trigger, int pitch, int volume, int id, uint64_t steamid64) {
	if (chatsounds_to_pcm.find(trigger) == chatsounds_to_pcm.end()) {
		printf("Unknown chatsound trigger '%s'\n", trigger.c_str());
		return NULL;
	}
	
	vector<int8_t>& loadedSamples = chatsounds_to_pcm[trigger];
	int numSamples = loadedSamples.size();
	int16_t* samples = new int16_t[numSamples];
	float scale = (float)volume / 100.0f;

	for (int i = 0; i < numSamples; i++) {
		float scaledSample = (loadedSamples[i] << 8) * scale;
		samples[i] = clampi(scaledSample, -32768, 32767);
	}

	if (numSamples % samplesPerPacket != 0) {
		int samplesToAdd = samplesPerPacket - (numSamples % samplesPerPacket);
		int16_t* paddedSamples = new int16_t[numSamples + samplesToAdd];
		memset((char*)(paddedSamples + numSamples), 0, samplesToAdd * sizeof(int16_t));
		memcpy(paddedSamples, samples, numSamples * sizeof(int16_t));

		delete[] samples;
		samples = paddedSamples;
		numSamples += samplesToAdd;
	}

	if (pitch != 100) {
		float speed = (float)pitch / 100;
		int estNewSampleCount = numSamples * (1.0f / speed) * 1.1f;
		int16_t* resampled = new int16_t[estNewSampleCount];

		numSamples = resamplePcm(samples, resampled, sampleRate, sampleRate * (1.0f / speed), numSamples);

		delete[] samples;
		samples = resampled;
	}

	string outputPath = svenRootPath + "/svencoop/scripts/plugins/temp/" + to_string(id) + ".spk";

	ofstream* outFile = new ofstream(outputPath);
	if (!outFile->good()) {
		fprintf(stderr, "Failed to open output file %s\n", outputPath.c_str());
		delete[] samples;
		delete outFile;
		return NULL;
	}

	SteamVoiceEncoder* encoder = new SteamVoiceEncoder(frameSize, framesPerPacket, sampleRate, opusBitrate, steamid64, OPUS_APPLICATION_AUDIO);
	return new ConvertJob(samples, numSamples, outFile, encoder);
}

bool ChatSoundConverter::convert(ConvertJob* job) {
	string packet = job->encoder->write_steam_voice_packet(job->samples + job->offset, samplesPerPacket);
	*(job->outFile) << packet << endl;

	job->offset += samplesPerPacket;

	bool finished = job->offset >= job->numSamples;
	
	// angelscript waits for a specific file size before playing.
	// really short sounds need some padding at the end.
	if (finished) {
		while (job->outFile->tellp() < 2048) {
			*(job->outFile) << "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";
		}
	}


	return finished;
}

ConvertJob::ConvertJob(int16_t* samples, int numSamples, ofstream* outFile, SteamVoiceEncoder* encoder) {
	this->samples = samples;
	this->numSamples = numSamples;
	this->outFile = outFile;
	this->encoder = encoder;
	offset = 0;
}

ConvertJob::~ConvertJob() {
	outFile->close();
	delete[] samples;
	delete outFile;
	delete encoder;
}
