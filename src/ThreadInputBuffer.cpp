#include "ThreadInputBuffer.h"
#include "pipes.h"
#include "stream_mp3.h"
#include <thread>
#include <cstring>

using namespace std;

ThreadInputBuffer::ThreadInputBuffer(size_t bufferSize)
{	
	this->bufferSize = bufferSize;
	this->writePos = 0;
	this->readPos = bufferSize; // no data left in buffer initially
	this->status.setValue(TIB_WRITE);
	writeBuffer = new char[bufferSize];
	readBuffer = new char[bufferSize];
	wasReceivingSamples = false;
	shouldNotifyPlayback = false;
	isPipe = false;
}

ThreadInputBuffer::~ThreadInputBuffer()
{
	inputThread.join();
	delete[] writeBuffer;
	delete[] readBuffer;
}

int ThreadInputBuffer::read(char* outputBuffer, size_t readSize)
{
	int curStatus = status.getValue();
	if (curStatus == TIB_KILL) {
		return -1;
	}

	size_t canRead = ::min(bufferSize - readPos, readSize);

	if (readSize > bufferSize) {
		return -1; // too large of a read for configured buffer size
	}
	
	if (canRead >= readSize) {
		memcpy(outputBuffer, readBuffer + readPos, canRead);
		readPos += canRead;
		return 0;
	}

	
	bool isFlushing = curStatus == TIB_FLUSH;

	if (curStatus != TIB_FULL && !isFlushing) {
		// need to grab input from write buffer, but can't because it's currently being written
		if (curStatus == TIB_FLUSHED) {
			size_t cantRead = readSize - canRead;
			memcpy(outputBuffer, readBuffer + readPos, canRead);
			memset(outputBuffer + canRead, 0, cantRead);
			status.setValue(TIB_FINISHED);
			return 0;
		}
		return -2;
	}

	memcpy(outputBuffer, readBuffer + readPos, canRead); // read what's left of the read buffer

	status.setValue(TIB_READ);
	// refill read buffer
	char* temp = readBuffer;
	readBuffer = writeBuffer;
	writeBuffer = temp;
	//fprintf(stderr, "Refilled read buffer\n");
	status.setValue(isFlushing ? TIB_FLUSHED : TIB_WRITE);
	if (isFlushing)
		fprintf(stderr, "Flushed output\n");

	// read what's left of readSize
	size_t readLeft = readSize - canRead;
	memcpy(outputBuffer + canRead, readBuffer, readLeft);
	readPos = readLeft;

	return 0;
}

size_t ThreadInputBuffer::write(char* inputBuffer, size_t inputSize)
{
	if (inputSize == 0) {
		return 0;
	}
	int val = status.getValue();

	if (val == TIB_FLUSH) {
		status.setValue(TIB_WRITE);
	}

	if (val != TIB_WRITE) {
		return 0;
	}

	if (!wasReceivingSamples) {
		shouldNotifyPlayback = true;
	}
	wasReceivingSamples = true;

	size_t canWrite = ::min(bufferSize - writePos, inputSize);
	memcpy(writeBuffer + writePos, inputBuffer, canWrite);
	writePos += canWrite;

	if (writePos >= bufferSize) {
		//fprintf(stderr, "Filled write buffer\n");
		status.setValue(TIB_FULL);
		writePos = 0;
	}

	return canWrite;
}

void ThreadInputBuffer::writeAll(char* inputBuffer, size_t inputSize)
{
	size_t bytesLeftToWrite = inputSize;
	size_t inputOffset = 0;

	while (bytesLeftToWrite && status.getValue() != TIB_KILL) {
		size_t written = write(inputBuffer + inputOffset, bytesLeftToWrite);
		bytesLeftToWrite -= written;
		inputOffset += written;

		if (written) {
			//fprintf(stderr, "Wrote %llu to input buffer\n", written);
		}
		else {
			//fprintf(stderr, "input buffer not ready for writing yet\n");
			std::this_thread::sleep_for(std::chrono::milliseconds(1));
		}
	}
}

void ThreadInputBuffer::flush()
{
	if (status.getValue() == TIB_WRITE) {
		memset(writeBuffer + writePos, 0, bufferSize - writePos);
		status.setValue(TIB_FLUSH);
	}
}

void ThreadInputBuffer::clear()
{
	int val = status.getValue();
	readPos = bufferSize;
	if (val == TIB_FULL || val == TIB_FINISHED) {
		status.setValue(TIB_WRITE);
		writePos = 0;
	}
	else {
		fprintf(stderr, "Could not reset %d\n", val);
	}
}

void ThreadInputBuffer::kill()
{
	status.setValue(TIB_KILL);
}

void ThreadInputBuffer::startPipeInputThread(std::string pipeName)
{
	this->resourceName = pipeName;
	this->inputThread = thread(readPipe, pipeName, this);
	this->isPipe = true;
}

void ThreadInputBuffer::startMp3InputThread(std::string fileName, int sampleRate, float volume, float speed)
{
	this->resourceName = fileName;
	this->inputThread = thread(streamMp3, fileName, this, sampleRate, volume, speed);
}

bool ThreadInputBuffer::isFinished()
{
	return status.getValue() == TIB_FINISHED || status.getValue() == TIB_KILL;
}
