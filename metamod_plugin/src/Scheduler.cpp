#include "Scheduler.h"
#include "meta_utils.h"

Scheduler::Scheduler() {}

void Scheduler::SetTimeout(void (*void_func) (void), float delay) {
	scheduler_void_func schedule = { void_func, delay, 0, 1, g_engfuncs.pfnTime()};

	void_func_schedules.push_back(schedule);
}

void Scheduler::SetInterval(void (*void_func) (void), float delay, int maxCalls) {
	scheduler_void_func schedule = { void_func, delay, 0, maxCalls, g_engfuncs.pfnTime() };

	void_func_schedules.push_back(schedule);
}

void Scheduler::SetTimeout(void (*int_func) (int), float delay, int param) {
	scheduler_int_func schedule = { int_func, param, delay, 0, 1, g_engfuncs.pfnTime() };

	int_func_schedules.push_back(schedule);
}

void Scheduler::SetInterval(void (*int_func) (int), float delay, int maxCalls, int param) {
	scheduler_int_func schedule = { int_func, param, delay, 0, maxCalls, g_engfuncs.pfnTime() };

	int_func_schedules.push_back(schedule);
}

void Scheduler::SetTimeout(void (*int_int_func) (int, int), float delay, int param1, int param2) {
	scheduler_int_int_func schedule = { int_int_func, param1, param2, delay, 0, 1, g_engfuncs.pfnTime() };

	int_int_func_schedules.push_back(schedule);
}

void Scheduler::SetInterval(void (*int_int_func) (int, int), float delay, int maxCalls, int param1, int param2) {
	scheduler_int_int_func schedule = { int_int_func, param1, param2, delay, 0, maxCalls, g_engfuncs.pfnTime() };

	int_int_func_schedules.push_back(schedule);
}

void Scheduler::SetTimeout(void (*str_bool_func) (std::string, bool), float delay, std::string param1, bool param2) {
	scheduler_str_bool_func schedule = { str_bool_func, param1, param2, delay, 0, 1, g_engfuncs.pfnTime() };

	str_bool_func_schedules.push_back(schedule);
}

void Scheduler::SetInterval(void (*str_bool_func) (std::string, bool), float delay, int maxCalls, std::string param1, bool param2) {
	scheduler_str_bool_func schedule = { str_bool_func, param1, param2, delay, 0, maxCalls, g_engfuncs.pfnTime() };

	str_bool_func_schedules.push_back(schedule);
}

void Scheduler::SetTimeout(void (*int_str_int_func) (int, std::string, int), float delay, int param1, std::string param2, int param3) {
	scheduler_int_str_int_func schedule = { int_str_int_func, param1, param2, param3, delay, 0, 1, g_engfuncs.pfnTime() };

	int_str_int_func_schedules.push_back(schedule);
}

void Scheduler::SetInterval(void (*int_str_int_func) (int, std::string, int), float delay, int maxCalls, int param1, std::string param2, int param3) {
	scheduler_int_str_int_func schedule = { int_str_int_func, param1, param2, param3, delay, 0, maxCalls, g_engfuncs.pfnTime() };

	int_str_int_func_schedules.push_back(schedule);
}

void Scheduler::Think() {
	float now = g_engfuncs.pfnTime();

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

	for (int i = 0; i < int_func_schedules.size(); i++) {
		scheduler_int_func& sched = int_func_schedules[i];

		if (now - sched.lastCall < sched.delay) {
			continue;
		}

		sched.func(sched.param);
		sched.lastCall = now;
		sched.callCount++;

		if (sched.maxCalls >= 0 && sched.callCount >= sched.maxCalls) {
			int_func_schedules.erase(int_func_schedules.begin() + i);
			i--;
		}
	}

	for (int i = 0; i < int_int_func_schedules.size(); i++) {
		scheduler_int_int_func& sched = int_int_func_schedules[i];

		if (now - sched.lastCall < sched.delay) {
			continue;
		}

		sched.func(sched.param1, sched.param2);
		sched.lastCall = now;
		sched.callCount++;

		if (sched.maxCalls >= 0 && sched.callCount >= sched.maxCalls) {
			int_int_func_schedules.erase(int_int_func_schedules.begin() + i);
			i--;
		}
	}

	for (int i = 0; i < int_str_int_func_schedules.size(); i++) {
		scheduler_int_str_int_func& sched = int_str_int_func_schedules[i];

		if (now - sched.lastCall < sched.delay) {
			continue;
		}

		sched.func(sched.param1, sched.param2, sched.param3);
		sched.lastCall = now;
		sched.callCount++;

		if (sched.maxCalls >= 0 && sched.callCount >= sched.maxCalls) {
			int_str_int_func_schedules.erase(int_str_int_func_schedules.begin() + i);
			i--;
		}
	}

	for (int i = 0; i < str_bool_func_schedules.size(); i++) {
		scheduler_str_bool_func& sched = str_bool_func_schedules[i];

		if (now - sched.lastCall < sched.delay) {
			continue;
		}

		sched.func(sched.param1, sched.param2);
		sched.lastCall = now;
		sched.callCount++;

		if (sched.maxCalls >= 0 && sched.callCount >= sched.maxCalls) {
			str_bool_func_schedules.erase(str_bool_func_schedules.begin() + i);
			i--;
		}
	}
}