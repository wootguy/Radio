#include <queue>
#include <string>
#include <mutex>
#include <thread>

class CommandQueue {
public:
	CommandQueue();

	bool hasCommand();
	std::string getNextCommand();
	void putCommand(std::string command);

private:
	std::thread inputThread;
	std::mutex queueLock;
	std::queue<std::string> commands;
};