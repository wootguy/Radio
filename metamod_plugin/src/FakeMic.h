#pragma once
#include "meta_utils.h"
#include "ThreadSafeQueue.h"

using namespace std;

struct VoicePacket {
	uint16 id;
	uint32_t size = 0;

	vector<string> sdata;
	vector<uint32_t> ldata;
	vector<uint8_t> data;

	VoicePacket() {}
	VoicePacket(const VoicePacket& other);
};

// call this every server frame
void FakeMicThink();
void play_samples();
void handle_radio_message(string msg);

extern ThreadSafeQueue<VoicePacket> g_voice_data_stream;