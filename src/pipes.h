#pragma once
#include <string>
#include <mutex>
#include "ThreadInputBuffer.h"

// read data from pipe into a buffer which the main thread can read from safely
void readPipe(std::string pipeName, ThreadInputBuffer* inputBuffer);