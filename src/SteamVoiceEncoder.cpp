#include "SteamVoiceEncoder.h"
#include <iostream>
#include <vector>
#include <iomanip>
#include "crc32.h"
#include <sstream>

using namespace std;

SteamVoiceEncoder::SteamVoiceEncoder(int frameSize, int framesPerPacket, int sampleRate, int bitrate,
	uint64_t steamid, int encodeMode)
{
	this->frameSize = frameSize;
	this->framesPerPacket = framesPerPacket;
	this->sampleRate = sampleRate;
	this->bitrate = bitrate;
	this->steamid = steamid;
	sequence = 0;

	int err = 0;
	encoder = opus_encoder_create(sampleRate, 1, encodeMode, &err);
	opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));

	if (err != OPUS_OK) {
		fprintf(stderr, "Failed to create opus encoder %d\n", err);
	}

	frameBuffer = new OpusFrame[framesPerPacket];

	//outFile = ofstream("../testing/replay.as");
	//outFile << "array<array<uint8>> replay = {\n";
}

SteamVoiceEncoder::~SteamVoiceEncoder()
{
	delete[] frameBuffer;
	delete encoder;
}

bool SteamVoiceEncoder::encode_opus_frame(int16_t* samples, OpusFrame& outFrame) {
	int length = opus_encode(encoder, samples, frameSize, outFrame.data, ENCODE_BUFFER_SIZE);

	if (length < 0) {
		fprintf(stderr, "Failed to encode %d\n", length);
		return false;
	}

	outFrame.length = length;
	outFrame.sequence = sequence++;

	return true;
}


string SteamVoiceEncoder::write_steam_voice_packet(int16_t* samples, int sampleLen) {

	if (sampleLen % (frameSize * framesPerPacket) != 0) {
		fprintf(stderr, "write_steam_voice_packet requires exactly %d samples\n", sampleLen);
		return "";
	}

	for (int i = 0; i < framesPerPacket; i++) {
		if (!encode_opus_frame(samples + i * frameSize, frameBuffer[i])) {
			return "";
		}
	}

	vector<uint8_t> packet;
	packet.reserve(512);
	packet.push_back((uint64_t)(steamid >> 0) & 0xff);
	packet.push_back((uint64_t)(steamid >> 8) & 0xff);
	packet.push_back((uint64_t)(steamid >> 16) & 0xff);
	packet.push_back((uint64_t)(steamid >> 24) & 0xff);
	packet.push_back((uint64_t)(steamid >> 32) & 0xff);
	packet.push_back((uint64_t)(steamid >> 40) & 0xff);
	packet.push_back((uint64_t)(steamid >> 48) & 0xff);
	packet.push_back((uint64_t)(steamid >> 56) & 0xff);

	packet.push_back(11);
	packet.push_back(sampleRate & 0xff);
	packet.push_back(sampleRate >> 8);
	packet.push_back(6);
	packet.push_back(0); // placeholder for payload length
	packet.push_back(0); // placeholder for payload length

	for (int k = 0; k < framesPerPacket; k++) {
		OpusFrame& frame = frameBuffer[k];

		uint16_t len = frame.length;
		uint16_t seq = frame.sequence;

		packet.push_back(len & 0xff);
		packet.push_back(len >> 8);
		packet.push_back(seq & 0xff);
		packet.push_back(seq >> 8);

		for (int b = 0; b < frame.length; b++) {
			packet.push_back(frame.data[b]);
		}
	}

	uint16_t payloadLength = (packet.size() + 4) - 18; // total packet size - header size
	packet[12] = payloadLength & 0xff;
	packet[13] = payloadLength >> 8;

	uint32_t crc32 = crc32_get(&packet[0], packet.size());
	packet.push_back((crc32 >> 0) & 0xff);
	packet.push_back((crc32 >> 8) & 0xff);
	packet.push_back((crc32 >> 16) & 0xff);
	packet.push_back((crc32 >> 24) & 0xff);

	static string hex_codes = "0123456789abcdef";

	string hexdata;
	for (int i = 0; i < packet.size(); i++) {
		hexdata += hex_codes[packet[i] >> 4];
		hexdata += hex_codes[packet[i] & 0xf];
	}

	/*
	if (packet.size() > 500) {
		fprintf(stderr, "TOO MUCH DATA %d\n", packet.size());
		return -1;
	}
	*/

	return hexdata;
}

void SteamVoiceEncoder::reset()
{
	opus_encoder_ctl(encoder, OPUS_RESET_STATE);
	sequence = 0;
}

void SteamVoiceEncoder::finishTestFile()
{
	outFile << "};\n";
	outFile.close();
}

void SteamVoiceEncoder::updateEncoderSettings(int bitrate)
{
	this->bitrate = bitrate;
	opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
}
