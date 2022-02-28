#pragma once
#include "ThreadInputBuffer.h"
#include <string>

void streamMp3(std::string fileName, ThreadInputBuffer* inputBuffer, int sampleRate, float volume, float speed);