#include <stdint.h>
#include <vector>
#include <string>
#include <iostream>
#include "pipes.h"
#include "ThreadInputBuffer.h"
#include "SteamVoiceEncoder.h"
#include "crc32.h"
#include "util.h"
#include "CommandQueue.h"
#include <cstring>
#include "pid.h"

#include "zita-resampler/resampler.h"

using namespace std;

#define MAX_CHANNELS 16
#define PIPE_BUFFER_SIZE 16384

// ffmpeg -i test.wav -y -f s16le -ar 12000 -ac 1 - >\\.\pipe\MicBotPipe0
// ffmpeg -i test.m4a -y -f s16le -ar 12000 -ac 1 - >\\.\pipe\MicBotPipe1
// TODO: output raw pcm, not WAV

vector<float> sample_rate_convert(float* input_samples, int input_count, int input_hz, int output_hz) {
	Resampler resampler;

	float ratio = (float)output_hz / (float)input_hz;
	int newSampleCount = ratio * input_count;
	//int newSampleCountSafe = newSampleCount + 256; // make sure there's enough room in the output buffer
	vector<float> output_samples;
	output_samples.resize(newSampleCount);

	resampler.setup(input_hz, output_hz, 1, 32);
	resampler.inp_count = input_count;
	resampler.inp_data = input_samples;
	resampler.out_count = newSampleCount;
	resampler.out_data = &output_samples[0];
	resampler.process();

	return output_samples;

}

int encodeFile(string inputPath, string outputPath, SteamVoiceEncoder* encoder, int sampleRate, int samplesPerPacket) {
	ThreadInputBuffer* stream = new ThreadInputBuffer(PIPE_BUFFER_SIZE);

	if (!fileExists(inputPath)) {
		fprintf(stderr, "Failed to open input file %s\n", inputPath.c_str());
		return 1;
	}

	ifstream inputFile(inputPath, ios::binary);
	wav_hdr header;

	inputFile.read((char*)&header, sizeof(header));

	if (header.RIFF[0] != 'R' || header.RIFF[1] != 'I' || header.RIFF[2] != 'F' || header.RIFF[3] != 'F') {
		fprintf(stderr, "ERROR: Invalid WAV file\n");
		return 1;
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
		return 1;
	}

	if (header.NumOfChan == 2) {
		numSamples = mixStereoToMono(newSamples, numSamples);
	}
	else if (header.NumOfChan != 1) {
		fprintf(stderr, "ERROR: Unexpected channel count %d\n", header.NumOfChan);
		return 1;
	}

	if (header.SamplesPerSec != sampleRate) {
		fprintf(stderr, "Resampling %d to %d\n", header.SamplesPerSec, sampleRate);

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

	if (numSamples % samplesPerPacket != 0) {
		int samplesToAdd = samplesPerPacket - (numSamples % samplesPerPacket);
		int16_t* paddedSamples = new int16_t[numSamples + samplesToAdd];
		memset((char*)(paddedSamples + numSamples), 0, samplesToAdd*sizeof(int16_t));
		memcpy(paddedSamples, newSamples, numSamples*sizeof(int16_t));

		delete[] newSamples;
		newSamples = paddedSamples;
		numSamples += samplesToAdd;
	}

	ofstream outFile(outputPath);
	if (!outFile.good()) {
		fprintf(stderr, "Failed to open output file %s\n", outputPath.c_str());
		return 1;
	}

	for (int i = 0; i < numSamples; i += samplesPerPacket) {
		string packet = encoder->write_steam_voice_packet(newSamples + i, samplesPerPacket);
		outFile << packet << endl;
	}
	outFile.close();

	/*
	{
		vector<int16_t> allSamples;
		for (int i = 0; i < numSamples; i++) {
			allSamples.push_back(newSamples[i]);
		}

		WriteOutputWav("hoho_test.wav", allSamples);
	}
	*/

	delete[] newSamples;

	fprintf(stderr, "Finished converion!\n");

	return 0;
}

int main(int argc, const char** argv)
{
	vector<ThreadInputBuffer*> inputStreams;
	int sampleRate = 12000; // opus allows: 8, 12, 16, 24, 48 khz
	int frameDuration = 10; // opus allows: 2.5, 5, 10, 20, 40, 60, 80, 100, 120
	int frameSize = (sampleRate / 1000) * frameDuration; // samples per frame
	int framesPerPacket = 5; // 2 = minimum amount of frames for sven to accept packet
	int packetDelay = frameDuration * framesPerPacket; // millesconds between output packets
	int samplesPerPacket = frameSize * framesPerPacket;
	int opusBitrate = 32000; // 32khz = steam default
	float globalVolume = 1.0f; // global volume adjustment
	const int packetStreams = 4; // individually mixed packet streams, for multiple voices

	// Steam ids need to be different per stream, if each stream is played at the same time.
	// Otherwise the client will try to combine the streams weridly and neither will work.
	uint64_t steam_w00tguy = 0x1100001025464b4; // w00tguy123
	uint64_t steam_w00tman = 0x110000112909743; // w00tman123
	uint64_t steam_min = 0x0110000100000001;
	uint64_t steam_max = 0x01100001FFFFFFFF;


	fprintf(stderr, "Sampling rate     : %d Hz\n", sampleRate);
	fprintf(stderr, "Frame size        : %d samples\n", frameSize);
	fprintf(stderr, "Frames per packet : %d\n", framesPerPacket);
	fprintf(stderr, "Samples per packet: %d\n", samplesPerPacket);
	fprintf(stderr, "Packet delay      : %d ms\n", packetDelay);
	fprintf(stderr, "Opus bitrate      : %d bps\n", opusBitrate);

	//getValidFrameConfigs();

	crc32_init();

	if (argc >= 4) {
		uint64_t steamid = steam_min + atoi(argv[3]);
		SteamVoiceEncoder* encoder = new SteamVoiceEncoder(frameSize, framesPerPacket, sampleRate, opusBitrate, steamid, OPUS_APPLICATION_AUDIO);
		return encodeFile(argv[1], argv[2], encoder, sampleRate, samplesPerPacket);
	}

	SteamVoiceEncoder* encoders[packetStreams];

	int16_t* inBuffer = new int16_t[samplesPerPacket];
	float* mixBuffer[packetStreams];
	int activeStreams[packetStreams];
	int16_t* outputBuffer = new int16_t[samplesPerPacket];
	long long nextPacketMillis = getTimeMillis();

	for (int i = 0; i < MAX_CHANNELS; i++) {
		ThreadInputBuffer* stream = new ThreadInputBuffer(PIPE_BUFFER_SIZE);
		stream->startPipeInputThread("MicBotPipe" + to_string(i));

		inputStreams.push_back(stream);
	}

	for (int i = 0; i < packetStreams; i++) {
		mixBuffer[i] = new float[samplesPerPacket];

		uint64_t steamid = steam_w00tguy;
		int encodeMode = OPUS_APPLICATION_AUDIO;
		if (i == packetStreams - 1) {
			steamid = steam_w00tman;
			encodeMode = OPUS_APPLICATION_VOIP;
		}

		encoders[i] = new SteamVoiceEncoder(frameSize, framesPerPacket, sampleRate, opusBitrate, steamid, encodeMode);
	}

	vector<int16_t> allSamples;

	int packetCount = 0;

	CommandQueue commands;
	commands.putCommand("play ../tts/tts0.mp3 1.0 1");

	while (1) {
		while (getTimeMillis() < nextPacketMillis) {
			std::this_thread::sleep_for(std::chrono::milliseconds(1));
		}

		nextPacketMillis += packetDelay;

		// the plugin plays packets 0.1ms faster than normal because otherwise the mic
		// starts to cut out after a minute or so. The packets should be generated
		// slightly faster too so that the plugin buffer doesn't deplete faster than it refills.
		if (packetCount++ % 10 == 0) {
			nextPacketMillis -= 1;
		}

		for (int i = 0; i < packetStreams; i++) {
			memset(mixBuffer[i], 0, samplesPerPacket * sizeof(float));
			activeStreams[i] = 0;
		}

		vector<ThreadInputBuffer*> newStreams;

		for (int i = 0; i < inputStreams.size(); i++) {
			if (inputStreams[i]->isFinished()) {
				if (inputStreams[i]->isPipe) {
					fprintf(stderr, "Reset %s\n", inputStreams[i]->resourceName.c_str());
					inputStreams[i]->clear();
					newStreams.push_back(inputStreams[i]);
					continue;
				}
				remove(inputStreams[i]->resourceName.c_str());
				fprintf(stderr, "Deleted %s\n", inputStreams[i]->resourceName.c_str());
				delete inputStreams[i];
				continue;
			}

			if (inputStreams[i]->shouldNotifyPlayback) {
				inputStreams[i]->shouldNotifyPlayback = false;
				printf("notify %s\n", inputStreams[i]->resourceName.c_str());
			}

			newStreams.push_back(inputStreams[i]);

			if (inputStreams[i]->read((char*)inBuffer, samplesPerPacket * sizeof(int16_t))) {
				// can't read yet
				if (inputStreams[i]->isPipe)
					inputStreams[i]->resetLoudnessNormalization();
				continue;
			}

			if (inputStreams[i]->isPipe)
				inputStreams[i]->loudnessNormalization(inBuffer, samplesPerPacket);

			int mixerChannel = inputStreams[i]->mixerChannel;
			activeStreams[mixerChannel]++;

			for (int k = 0; k < samplesPerPacket; k++) {
				mixBuffer[mixerChannel][k] += ((float)inBuffer[k] / 32768.0f) * inputStreams[i]->volume;
			}
		}
		inputStreams = newStreams; // remove any finished streamds

		// merge all packet stream data into a single line
		string packetClump = "";
		for (int i = 0; i < packetStreams; i++) {
			if (i > 0)
				packetClump += ":";

			if (activeStreams[i]) {
				for (int k = 0; k < samplesPerPacket; k++) {
					outputBuffer[k] = clampf(mixBuffer[i][k], -1.0f, 1.0f) * 32767.0f;
				}
				packetClump += encoders[i]->write_steam_voice_packet(outputBuffer, samplesPerPacket);
			}
			else {
				packetClump += "ff"; // no packets are ever this small. The plugin will know to replace this with silence
			}
		}
		cout << packetClump << endl;
		fflush(stdout);


		//fprintf(stderr, "Total streams %d\n", inputStreams.size());

		while (commands.hasCommand()) {
			string command = commands.getNextCommand();

			if (command.find("play") == 0) {
				vector<string> args = splitString(command, " ");
				if (args.size() < 4) {
					fprintf(stderr, "Wrong number of args in play command: %s\n", command.c_str());
					continue;
				}
				string fname = args[1];
				string svol = args[2];
				string speed = args[3];
				float volume = atof(svol.c_str());
				float fspeed = atof(speed.c_str());

				ThreadInputBuffer* mp3Input = new ThreadInputBuffer(PIPE_BUFFER_SIZE);
				mp3Input->mixerChannel = packetStreams - 1; // last channel for tts
				mp3Input->startMp3InputThread(fname, sampleRate, volume, fspeed);
				inputStreams.push_back(mp3Input);
				fprintf(stderr, "Play %s (%.2f x%.2f)\n", fname.c_str(), volume, fspeed);
			}

			if (command.find("notify") == 0) {
				string id = command.substr(strlen("notify "));

				for (int i = 0; i < inputStreams.size(); i++) {
					if (inputStreams[i]->resourceName == id) {
						fprintf(stderr, "Notify '%s'\n", id.c_str());
						inputStreams[i]->wasReceivingSamples = false;
						inputStreams[i]->shouldNotifyPlayback = false;
					}
				}
			}

			if (command.find("stop") == 0) {
				string id = command.substr(strlen("stop "));

				for (int i = 0; i < inputStreams.size(); i++) {
					if (inputStreams[i]->resourceName == id) {
						if (id.find(".mp3") != string::npos) {
							fprintf(stderr, "Killing '%s'\n", id.c_str());
							inputStreams[i]->kill();
						}
						else {
							fprintf(stderr, "Stopping '%s'\n", id.c_str());
							inputStreams[i]->clear();
						}
					}
				}
			}

			if (command.find("assign") == 0) {
				vector<string> args = splitString(command, " ");
				if (args.size() < 3) {
					fprintf(stderr, "Wrong number of args in assign command: %s\n", command.c_str());
					continue;
				}
				string id = args[1];
				int channelId = atoi(args[2].c_str());

				for (int i = 0; i < inputStreams.size(); i++) {
					if (inputStreams[i]->resourceName == id) {
						fprintf(stderr, "Assigned '%s' to channel %d\n", id.c_str(), channelId);
						inputStreams[i]->mixerChannel = channelId;
					}
				}
			}

			if (command.find("settings") == 0) {
				vector<string> args = splitString(command, " ");
				if (args.size() != 2) {
					fprintf(stderr, "Wrong number of args in assign command: %s\n", command.c_str());
					continue;
				}
				int bitrate = atoi(args[1].c_str());
				opusBitrate = bitrate;

				for (int i = 0; i < packetStreams; i++) {
					encoders[i]->updateEncoderSettings(bitrate);
				}

				fprintf(stderr, "Bitrate set to %d\n", bitrate);
			}
		}
	}

	return 0;
}
