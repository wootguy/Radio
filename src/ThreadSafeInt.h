#pragma once
#include <mutex>

class ThreadSafeInt {
public:
	int getValue();
	void setValue(int value);

private:
	std::mutex mutex;
	int value;
};