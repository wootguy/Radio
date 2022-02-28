#include "ThreadSafeInt.h"

using namespace std;

int ThreadSafeInt::getValue() {
	mutex.lock();
	int ret = value;
	mutex.unlock();

	return ret;
}

void ThreadSafeInt::setValue(int val) {
	mutex.lock();
	value = val;
	mutex.unlock();
}