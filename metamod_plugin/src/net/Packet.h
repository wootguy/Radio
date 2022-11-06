#pragma once
#include "IPV4.h"

// maximum size before fragmentation.
// MTU for IPV4 UDP is 576 byte. 
// IP headers can be between 20 and 60 bytes.
// UDP headers are always 8 bytes. 
// 576 - 68 = 508
//#define MAX_PACKET_SIZE 508

#define MAX_PACKET_SIZE 4096 // fragmentation is ok for this program

class Packet
{
public:
	IPV4 addr; // destination/source address
	char * data = NULL;
	int sz = -1;

	Packet(const string& message);

	Packet(const string& message, IPV4 addr);

	Packet(IPV4 addr, void * data, int sz);
	
	Packet(const void * data, int sz);

	string getString();

	Packet();

	~Packet();

private:
	void init(const string& message);
};