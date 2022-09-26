#include "Scheduler.h"
#include "perf_counter.h"

static CPerformanceCounter perfCounter;

Scheduler::Scheduler() {}

void Scheduler::setTimeout(void (*void_func) (void), float delay) {
	scheduler_void_func schedule = { void_func, delay, 0, 1, perfCounter.GetCurTime() };

	void_func_schedules.push_back(schedule);
}

void Scheduler::setInterval(void (*void_func) (void), float delay, int maxCalls) {
	scheduler_void_func schedule = { void_func, delay, 0, maxCalls, perfCounter.GetCurTime() };

	void_func_schedules.push_back(schedule);
}

void Scheduler::think() {
	double now = perfCounter.GetCurTime();

	for (int i = 0; i < void_func_schedules.size(); i++) {
		scheduler_void_func& sched = void_func_schedules[i];

		if (now - sched.lastCall < sched.delay) {
			continue;
		}

		sched.func();
		sched.lastCall = now;
		sched.callCount++;

		if (sched.maxCalls >= 0 && sched.callCount >= sched.maxCalls) {
			void_func_schedules.erase(void_func_schedules.begin() + i);
			i--;
		}
	}
}