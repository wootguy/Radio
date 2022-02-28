#include "CommandQueue.h"
#include <iostream>

using namespace std;

void commandThread(CommandQueue* queue) {
    for (std::string line; std::getline(std::cin, line);) {
        queue->putCommand(line);
    }
}

CommandQueue::CommandQueue() {
    inputThread = thread(commandThread, this);
}

bool CommandQueue::hasCommand()
{
    queueLock.lock();
    bool ret = !commands.empty();
    queueLock.unlock();

    return ret;
}

std::string CommandQueue::getNextCommand()
{
    if (!hasCommand()) {
        return "";
    }

    queueLock.lock();
    string ret = commands.front();
    commands.pop();
    queueLock.unlock();

    return ret;
}

void CommandQueue::putCommand(std::string command)
{
    queueLock.lock();
    commands.push(command);
    queueLock.unlock();
}
