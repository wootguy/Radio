#include "util.h"
#include <fstream>
#include <string.h>
#include <chrono>

#include "zita-resampler/resampler.h"

using namespace std;
using std::chrono::milliseconds;
using std::chrono::duration_cast;
using std::chrono::system_clock;

float clampf(float val, float min, float max) {
	if (val > max) {
		return max;
	}
	else if (val < min) {
		return min;
	}

	return val;
}

int clampi(int val, int min, int max) {
	if (val > max) {
		return max;
	}
	else if (val < min) {
		return min;
	}

	return val;
}

void WriteOutputWav(string fname, vector<int16_t>& allSamples) {
	wav_hdr header;
	header.ChunkSize = allSamples.size() * 2 + sizeof(wav_hdr) - 8;
	header.Subchunk2Size = allSamples.size() * 2 + sizeof(wav_hdr) - 44;

	ofstream out(fname, ios::binary);
	out.write(reinterpret_cast<const char*>(&header), sizeof(header));

	for (int z = 0; z < allSamples.size(); z++) {
		out.write(reinterpret_cast<char*>(&allSamples[z]), sizeof(int16_t));
	}

	out.close();
	fprintf(stderr, "Wrote file!\n");
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

long long getTimeMillis() {
	return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

bool fileExists(const std::string& name) {
	if (FILE* file = fopen(name.c_str(), "r")) {
		fclose(file);
		return true;
	}
	else {
		return false;
	}
}

int resamplePcm(int16_t* pcm_old, int16_t* pcm_new, int oldRate, int newRate, int numSamples) {
	float samplesPerStep = (float)oldRate / newRate;
	int numSamplesNew = (float)numSamples / samplesPerStep;
	float t = 0;

	for (int i = 0; i < numSamplesNew; i++) {
		int newIdx = t;
		pcm_new[i] = pcm_old[newIdx];
		t += samplesPerStep;
	}

	return numSamplesNew;
}

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

// mixes samples in-place without a new array
int mixStereoToMono(int16_t* pcm, int numSamples) {

	for (int i = 0; i < numSamples / 2; i++) {
		float left = ((float)pcm[i * 2] / 32768.0f);
		float right = ((float)pcm[i * 2 + 1] / 32768.0f);
		pcm[i] = clampf(left + right, -1.0f, 1.0f) * 32767;
	}

	return numSamples / 2;
}

void amplify(int16_t* pcm, int numSamples, double volume) {
	for (int i = 0; i < numSamples; i++) {
		double samp = ((double)pcm[i] / 32768.0f);
		pcm[i] = clampf(samp * volume, -1.0f, 1.0f) * 32767;
	}
}