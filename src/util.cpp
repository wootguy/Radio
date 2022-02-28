#include "util.h"
#include <fstream>
#include <string.h>
#include <chrono>

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