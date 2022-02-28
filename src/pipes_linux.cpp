#ifndef WIN32

#include "pipes.h"
#include <string>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

using namespace std;

int exists(const char* fname)
{
	FILE* file;
	if ((file = fopen(fname, "r")))
	{
		fclose(file);
		return 1;
	}
	return 0;
}

void readPipe(string pipeName, ThreadInputBuffer* inputBuffer) {
	if (exists(pipeName.c_str())) {
		remove(pipeName.c_str());
	}

	if (mkfifo(pipeName.c_str(), 0666)) {
		fprintf(stderr, "Failed to make fifo: %s\n", pipeName.c_str());
		return;
	}

	int fifo = open(pipeName.c_str(), O_RDONLY);

	if (fifo < 0) {
		fprintf(stderr, "Failed to open fifo: %s\n", pipeName.c_str());
		return;
	}
	fprintf(stderr, "Opened fifo: %s\n", pipeName.c_str());

	char buffer[1024];
	int lastRead = 0;

	while (true) {
		int bytesRead = read(fifo, buffer, 1024);
		inputBuffer->writeAll(buffer, bytesRead);

		if (bytesRead == 0) {
			if (lastRead != 0) {
				inputBuffer->flush();
			}
			
			std::this_thread::sleep_for(std::chrono::milliseconds(1));
		}

		lastRead = bytesRead;
	}

	//close(fifo);
}

#endif