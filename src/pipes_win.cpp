#ifdef WIN32
#include "pipes.h"
#include <Windows.h>
#include <vector>
#include <map>
#include <thread>
#include <chrono>

using namespace std;

map<string, HANDLE> g_pipes;

HANDLE createInputPipe(std::string id) {
    HANDLE hPipe;
    string pipeName = "\\\\.\\pipe\\" + id;

    hPipe = CreateNamedPipe(TEXT(pipeName.c_str()),
        PIPE_ACCESS_INBOUND,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,   // FILE_FLAG_FIRST_PIPE_INSTANCE is not needed but forces CreateNamedPipe(..) to fail if the pipe already exists...
        1,
        1024 * 16,
        1024 * 16,
        NMPWAIT_USE_DEFAULT_WAIT,
        NULL);

    if (hPipe == INVALID_HANDLE_VALUE) {
        fprintf(stderr, "Failed to create pipe\n");
        return "";
    }

    g_pipes.insert(make_pair(pipeName, hPipe));
    return hPipe;
}

void readPipe(string pipeName, ThreadInputBuffer* inputBuffer) {
    HANDLE hPipe = createInputPipe(pipeName);

    char buffer[1024];

    while (1) {
        fprintf(stderr, "Connecting pipe %s\n", pipeName.c_str());
        if (ConnectNamedPipe(hPipe, NULL) != FALSE)   // wait for someone to connect to the pipe
        {
            while (1) {
                DWORD bytesRead;

                if (ReadFile(hPipe, buffer, sizeof(buffer), &bytesRead, NULL) != FALSE)
                {
                    inputBuffer->writeAll(buffer, bytesRead);
                }
                else {
                    fprintf(stderr, "No data in pipe\n");
                    inputBuffer->flush();
                    DisconnectNamedPipe(hPipe);
                    break;
                }
            }
        }
        else {
            fprintf(stderr, "Can't connect to pipe\n");
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }
}

#endif