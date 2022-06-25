#include "stream_mp3.h"
#include "util.h"
#include <stdio.h>
#include <vector>
#include <fstream>

// https://github.com/lieff/minimp3
#define MINIMP3_IMPLEMENTATION
//#define MINIMP3_ONLY_MP3
#include "minimp3.h"

using namespace std;

void streamMp3(string fileName, ThreadInputBuffer* inputBuffer, int sampleRate, float volume, float speed) {
	const float minSpeed = 0.1f;
	if (speed <= minSpeed) {
		speed = minSpeed;
	}
	
	FILE* file = fopen(fileName.c_str(), "rb");
	if (!file) {
		fprintf(stderr, "Unable to open: %s\n", fileName.c_str());
		return;
	}

	mp3dec_t mp3d;
	mp3dec_init(&mp3d);

	int16_t pcm[MINIMP3_MAX_SAMPLES_PER_FRAME];
	int16_t* resampledPcm = new int16_t[(int)(MINIMP3_MAX_SAMPLES_PER_FRAME*(1.0f / minSpeed))];
	uint8_t* buffer = new uint8_t[16384];

	const int bufferSize = 16384; // 16kb = recommended minimum
	int readPos = 0;
	int readSize = 16384;
	int bufferLeft = 0;

	vector<int16_t> allSamples;

	while (!inputBuffer->isFinished()) {
		int readBytes = fread(buffer + readPos, 1, readSize, file);
		if (readBytes == 0 && bufferLeft == 0) {
			break;
		}
		bufferLeft += readBytes;

		mp3dec_frame_info_t info;
		int samples = mp3dec_decode_frame(&mp3d, buffer, bufferLeft, pcm, &info);
		samples *= info.channels;

		// remove the read bytes from the buffer
		int bytesRead = info.frame_bytes;
		memmove(buffer, buffer + bytesRead, bufferSize - bytesRead);
		readSize = bytesRead;
		readPos = bufferSize - bytesRead;
		bufferLeft -= bytesRead;

		if (info.channels == 2) {
			samples = mixStereoToMono(pcm, samples);
		}

		int writeSamples = resamplePcm(pcm, resampledPcm, info.hz, 12000*(1.0f/speed), samples);
		//int writeSamples = samples;
		//memcpy(resampledPcm, pcm, writeSamples*sizeof(int16_t));

		if (volume != 1.0f) {
			amplify(resampledPcm, writeSamples, volume);
		}

		inputBuffer->writeAll((char*)resampledPcm, writeSamples * sizeof(int16_t));
	}
	
	delete[] resampledPcm;
	delete[] buffer;
	inputBuffer->flush();
	fclose(file);
}