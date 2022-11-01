#pragma once
#include "ThreadSafeQueue.h"
#include "radio_utils.h"

extern ThreadSafeQueue<string> g_commands_out;
extern ThreadSafeQueue<string> g_commands_in;
extern ThreadSafeQueue<string> g_packet_input;

void command_socket_thread(const char* addr);
void voice_socket_thread(const char* addr);

void start_network_threads();
void stop_network_threads();