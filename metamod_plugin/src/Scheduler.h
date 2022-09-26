#include <vector>

// shitty version of the angelscript scheduler
// every type of function that can be called must have its own methods and struct

struct scheduler_void_func {
	void (*func)(void);
	float delay;	
	int callCount;
	int maxCalls; // infinite if < 0
	float lastCall;
};

class Scheduler {
public:
	Scheduler();

	void setTimeout(void (*void_func) (void), float delay);
	void setInterval(void (*void_func) (void), float delay, int maxCalls);

	void think();

private:
	std::vector<scheduler_void_func> void_func_schedules;
};