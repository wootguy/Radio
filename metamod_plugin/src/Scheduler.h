#pragma once
#include <vector>
#include <string>

// shitty version of the angelscript scheduler
// every type of function that can be called must have its own methods and struct

struct scheduler_void_func {
	void (*func)(void);
	float delay;	
	int callCount;
	int maxCalls; // infinite if < 0
	float lastCall;
};

struct scheduler_int_func {
	void (*func)(int);
	int param;
	float delay;
	int callCount;
	int maxCalls; // infinite if < 0
	float lastCall;
};

struct scheduler_int_int_func {
	void (*func)(int, int);
	int param1;
	int param2;
	float delay;
	int callCount;
	int maxCalls; // infinite if < 0
	float lastCall;
};

struct scheduler_int_str_int_func {
	void (*func)(int, std::string, int);
	int param1;
	std::string param2;
	int param3;
	float delay;
	int callCount;
	int maxCalls; // infinite if < 0
	float lastCall;
};

struct scheduler_str_bool_func {
	void (*func)(std::string, bool);
	std::string param1;
	bool param2;
	float delay;
	int callCount;
	int maxCalls; // infinite if < 0
	float lastCall;
};

class Scheduler {
public:
	Scheduler();

	void SetTimeout(void (*void_func) (void), float delay);
	void SetInterval(void (*void_func) (void), float delay, int maxCalls);

	void SetTimeout(void (*int_func) (int), float delay, int param);
	void SetInterval(void (*int_func) (int), float delay, int maxCalls, int param);

	void SetTimeout(void (*int_int_func) (int, int), float delay, int param1, int param2);
	void SetInterval(void (*int_int_func) (int, int), float delay, int maxCalls, int param1, int param2);

	void SetTimeout(void (*str_bool_func) (std::string, bool), float delay, std::string param1, bool param2);
	void SetInterval(void (*str_bool_func) (std::string, bool), float delay, int maxCalls, std::string param1, bool param2);

	void SetTimeout(void (*int_str_int_func) (int, std::string, int), float delay, int param1, std::string param2, int param3);
	void SetInterval(void (*int_str_int_func) (int, std::string, int), float delay, int maxCalls, int param1, std::string param2, int param3);

	void Think();

private:
	std::vector<scheduler_void_func> void_func_schedules;
	std::vector<scheduler_int_func> int_func_schedules;
	std::vector<scheduler_int_int_func> int_int_func_schedules;
	std::vector<scheduler_int_str_int_func> int_str_int_func_schedules;
	std::vector<scheduler_str_bool_func> str_bool_func_schedules;
};