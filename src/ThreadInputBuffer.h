#pragma once
#include "ThreadSafeInt.h"
#include <thread>
#include "pid.h"

enum BUFFER_STATUS {
	TIB_FULL,  // input buffer is full and ready to be read
	TIB_WRITE, // input buffer can be or is currently being written to by a pipe thread.
	TIB_READ,  // input buffer is currently being read from the main thread. No writing allowed.
	TIB_FLUSH, // input buffer can't be written to anymore. Reader should take whatever is left.
	TIB_FLUSHED, // reader took the last of the input data from the write buffer
	TIB_FINISHED, // reader read the last of the flushed data
	TIB_KILL, // thread should kill itself and data should no longer be read
};

#define RMS_HISTORY_SIZE 20 // should be based on audio duration per packet but isn't

class ThreadInputBuffer {
public:
	std::string resourceName; // pipe or file name

	// for sending messages when a video starts playing
	bool wasReceivingSamples;
	bool shouldNotifyPlayback;
	bool isPipe;
	int mixerChannel; // which packet stream to write to
	
	// loudness normalization
	float volume;
	pid_ctrl_t pid;
	float idealRms; // target loudness
	int rmsIdx;
	float rmsOld[RMS_HISTORY_SIZE];

	ThreadInputBuffer(size_t bufferSize);
	~ThreadInputBuffer();

	// call from the main thread to read data from a pipe
	// returns 0 on success, 1 for failure
	int read(char* outputBuffer, size_t readSize);

	// call from the pipe thread to add data to the buffer
	// returns bytes that were actually written
	size_t write(char* inputBuffer, size_t inputSize);

	// like write but will block if the write can't complete yet
	void writeAll(char* inputBuffer, size_t inputSize);

	// finish a write before the buffer is full
	void flush();

	// clear buffers to stop them being consudmed
	void clear();

	// reset for more writing after being completely emptied
	void reset();

	// stop the input thread and any more reads
	void kill();

	void startPipeInputThread(std::string pipeName);

	void startMp3InputThread(std::string fileName, int sampleRate, float volume, float speed);

	bool isFinished(); // true if input thread was terminated

	void loudnessNormalization(int16_t* samples, int numSamples);

	void resetLoudnessNormalization();

private:
	std::thread inputThread;

	ThreadSafeInt status; // used to prevent multiple threads reading/writing to the writeBuffer

	char* writeBuffer; // data written to by pipe thread
	char* readBuffer;  // data which can be read while threadData is written
	size_t bufferSize;
	size_t writePos;
	size_t readPos;
};