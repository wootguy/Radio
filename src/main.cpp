#include <stdint.h>
#include <vector>
#include <string>
#include <fstream>
#include <thread>
#include <chrono>
#include <iostream>
#include "pipes.h"
#include "ThreadInputBuffer.h"
#include "SteamVoiceEncoder.h"
#include "crc32.h"
#include "util.h"
#include "CommandQueue.h"
#include <cstring>
#include <math.h> 
#include "pid.h"

using namespace std;
using std::chrono::milliseconds;
using std::chrono::duration_cast;
using std::chrono::system_clock;

#define MAX_CHANNELS 16
#define PIPE_BUFFER_SIZE 16384

// ffmpeg -i test.wav -y -f s16le -ar 12000 -ac 1 - >\\.\pipe\MicBotPipe0
// ffmpeg -i test.m4a -y -f s16le -ar 12000 -ac 1 - >\\.\pipe\MicBotPipe1
// TODO: output raw pcm, not WAV

// Best packet delays:
//     Bitrate: 16000, SampleRate: 12000, Frames 1200 x 2, MaxSz: 478, delay: 0.200

void getValidFrameConfigs() {
	const int randomSampleSize = 1024*256;
	const int sampleRateCount = 1;
	const int frameDurationCount = 9;
	const int bitrateCount = 6;
	const int maxFramesPerPacket = 8;
	const float minPacketDelay = 0.05f; // script shouldn't send too fast

	uint8_t buffer[1024];
	int16_t* randomSamples;
	randomSamples = new int16_t[randomSampleSize];

	//int sampleRates[sampleRateCount] = {8000, 12000, 16000, 24000, 48000};
	int sampleRates[sampleRateCount] = {12000};
	//float frameDurations[frameDurationCount] = {2.5, 5, 10, 20, 40, 60, 80, 100, 120};
	float frameDurations[frameDurationCount] = {10, 20, 40, 60, 80, 100, 120};
	float bitrates[bitrateCount] = {16000, 22000, 24000, 28000, 32000, 64000};

	for (int i = 0; i < randomSampleSize; i++) {
		randomSamples[i] = rand() % 65536;
	}

	for (int b = 0; b < bitrateCount; b++) {
		int bitrate = bitrates[b];

		for (int r = 0; r < sampleRateCount; r++) {
			int sampleRate = sampleRates[r];
			fprintf(stderr, "\n");
			for (int i = 0; i < frameDurationCount; i++) {
				int frameSize = ((sampleRate / 1000) * frameDurations[i]) + 0.5f;

				for (int framesPerPacket = 2; framesPerPacket <= maxFramesPerPacket; framesPerPacket++) {
					SteamVoiceEncoder encoder(frameSize, framesPerPacket, sampleRate, bitrate);
					int samplesPerPacket = frameSize * framesPerPacket;

					float delay = (frameDurations[i] * framesPerPacket) / 1000.0f;
					if (delay < minPacketDelay) {
						continue; // too fast
					}

					int maxPacketSize = 0;
					for (int i = 0; i < randomSampleSize - samplesPerPacket; i += samplesPerPacket) {
						int sz = encoder.write_steam_voice_packet(randomSamples + i, samplesPerPacket);

						if (sz == -1) {
							fprintf(stderr, "Failed to encode\n");
						}
						if (sz > maxPacketSize) {
							maxPacketSize = sz;
						}
						if (maxPacketSize > 500) {
							break;
						}
					}

					if (maxPacketSize == 0) {
						fprintf(stderr, "uhhh\n");
					}

					if (maxPacketSize <= 500) {
						fprintf(stderr, "Bitrate: %d, SampleRate: %d, Frames %d x %d, MaxSz: %d, delay: %.3f, frameDur: %.1f\n",
							bitrate, sampleRate, frameSize, framesPerPacket, maxPacketSize, delay, frameDurations[i]);
					}
				}
			}
		}
	}
}

void pipe_test() {
	vector<ThreadInputBuffer*> inputStreams;
	int sampleRate = 12000; // opus allows: 8, 12, 16, 24, 48 khz
	int frameDuration = 10; // opus allows: 2.5, 5, 10, 20, 40, 60, 80, 100, 120
	int frameSize = (sampleRate / 1000) * frameDuration; // samples per frame
	int framesPerPacket = 5; // 2 = minimum amount of frames for sven to accept packet
	int packetDelay = frameDuration*framesPerPacket; // millesconds between output packets
	int samplesPerPacket = frameSize*framesPerPacket;
	int opusBitrate = 32000; // 32khz = steam default
	float globalVolume = 1.0f; // global volume adjustment

	fprintf(stderr, "Sampling rate     : %d Hz\n", sampleRate);
	fprintf(stderr, "Frame size        : %d samples\n", frameSize);
	fprintf(stderr, "Frames per packet : %d\n", framesPerPacket);
	fprintf(stderr, "Samples per packet: %d\n", samplesPerPacket);
	fprintf(stderr, "Packet delay      : %d ms\n", packetDelay);
	fprintf(stderr, "Opus bitrate      : %d bps\n", opusBitrate);

	//getValidFrameConfigs();

	crc32_init();
	SteamVoiceEncoder encoder(frameSize, framesPerPacket, sampleRate, opusBitrate);
	
	int16_t* inBuffer = new int16_t[samplesPerPacket];
	float* mixBuffer = new float[samplesPerPacket];
	int16_t* outputBuffer = new int16_t[samplesPerPacket];
	long long nextPacketMillis = getTimeMillis();

	for (int i = 0; i < MAX_CHANNELS; i++) {
		ThreadInputBuffer* stream = new ThreadInputBuffer(PIPE_BUFFER_SIZE);
		stream->startPipeInputThread("MicBotPipe" + to_string(i));

		inputStreams.push_back(stream);
	}

	vector<int16_t> allSamples;

	int packetCount = 0;

	CommandQueue commands;
	commands.putCommand("play ../tts/tts0.mp3 1.0 1");

	float idealDb = -16.0f;
	float idealRms = 0.18f;
	const int maxAmpSize = 20;
	float maxAmps[maxAmpSize];
	float rmsOld[maxAmpSize];
	int maxAmpIdx = 0;

	for (int i = 0; i < maxAmpSize; i++) {
		maxAmps[i] = idealDb;
		rmsOld[i] = idealRms;
	}

	// Control loop gains
	float kp = 0.2f; // how fast the system responds
	float ki = 0.0f;
	float kd = 1.0f;

	pid_ctrl_t pid;
	pid_init(&pid);

	/* PD controller. */
	pid_set_gains(&pid, kp, ki, kd);

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

		memset(mixBuffer, 0, samplesPerPacket*sizeof(float));
		
		vector<ThreadInputBuffer*> newStreams;

		int activeStreams = 0;
		for (int i = 0; i < inputStreams.size(); i++) {
			if (inputStreams[i]->isFinished()) {
				if (inputStreams[i]->isPipe) {
					fprintf(stderr, "Reset %s\n", inputStreams[i]->resourceName.c_str());
					inputStreams[i]->clear();
					newStreams.push_back(inputStreams[i]);
					continue;
				}
				fprintf(stderr, "Finished %s\n", inputStreams[i]->resourceName.c_str());
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
				continue;
			}

			activeStreams++;
			// ../tts/tts0.mp3
			for (int k = 0; k < samplesPerPacket; k++) {
				mixBuffer[k] += (float)inBuffer[k] / 32768.0f;
			}
		}

		if (activeStreams) {
			//fprintf(stderr, "Mixed %d samples from %d streams\n", samplesPerPacket, activeStreamds);

			float rmsSum = 0;

			for (int k = 0; k < samplesPerPacket; k++) {
				int16_t samp = clampf(mixBuffer[k] * globalVolume, -1.0f, 1.0f) * 32767.0f;
				float amp = (abs(samp) / 32768.0f);
				rmsSum += amp * amp;
				
				outputBuffer[k] = samp;
				//allSamples.push_back(outputBuffer[k]);
			}

			float rms = sqrt(rmsSum / samplesPerPacket);
			float decibel = 20 * log10(rms);

			bool silentPart = maxAmpIdx++ < maxAmpSize || decibel < -50;
			if (!silentPart) {
				maxAmps[maxAmpIdx % maxAmpSize] = decibel;
				rmsOld[maxAmpIdx % maxAmpSize] = rms;
			}

			float avgDb = 0;
			float avgRms = 0;
			for (int k = 0; k < maxAmpSize; k++) {
				avgDb += maxAmps[k];
				avgRms += rmsOld[k];
			}
			avgDb /= maxAmpSize;
			avgRms /= maxAmpSize;

			float error = avgRms - idealRms;

			float pidWant = 0;
			if (!silentPart) {
				pidWant = pid_process(&pid, error);

				globalVolume += pidWant;
				if (globalVolume != globalVolume || isinf(globalVolume)) {
					globalVolume = 1.0f;
				}
				if (globalVolume <= 0.1f) {
					globalVolume = 0.1f;
				}
			}

			fprintf(stderr, "dB %2.1f, RMS %.3f Error %+.3f, Vol %.2f, %s\n", avgDb, avgRms, error, globalVolume, silentPart ? "silent" : "");

			encoder.write_steam_voice_packet(outputBuffer, samplesPerPacket);
		}
		else {
			//fprintf(stderr, "No active streamds\n");			
			printf("SILENCE\n");

			if (globalVolume != 1.0f) {
				globalVolume = 1.0f;
				for (int i = 0; i < maxAmpSize; i++) {
					maxAmps[i] = idealDb;
					rmsOld[i] = idealRms;
				}
			}
			
			/*
			if (allSamples.size()) {
				WriteOutputWav("mixer.wav", allSamples);
				printf("BOKAY");
			}
			*/
		}
		fflush(stdout);

		inputStreams = newStreams; // remove any finished streamds
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
		}
	}
}

int main(int argc, const char **argv)
{
	pipe_test();

	return 0;
}
