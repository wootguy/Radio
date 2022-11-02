#pragma once
#include "meta_utils.h" // linux needs this here to fix min/max macro conflicts
#include "ThreadSafeQueue.h"
#include <string>

extern ThreadSafeQueue<std::string> g_commands_out;
extern ThreadSafeQueue<std::string> g_commands_in;
extern ThreadSafeQueue<std::string> g_packet_input;

void command_socket_thread(const char* addr);
void voice_socket_thread(const char* addr);

void start_network_threads();
void stop_network_threads();