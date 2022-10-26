#pragma once
#include "meta_utils.h"

struct VoicePacket {
	uint16 id;
	uint32_t size = 0;

	vector<string> sdata;
	vector<uint32_t> ldata;
	vector<uint8_t> data;
};

// call this every server frame
void FakeMicThink();
void load_samples();
void play_samples();
void load_packets_from_file();