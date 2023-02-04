#pragma once
#include <vector>
#include <functional>

struct ScheduledFunction {
    std::function<void()> func;
    float delay;
    int callCount;
    int maxCalls; // infinite if < 0
    float lastCall;
};

class Scheduler {
public:
    Scheduler() {}

    template <typename F, typename... Args>
    void SetTimeout(F&& func, float delay, Args&&... args) {
        ScheduledFunction f = {
            std::bind(std::forward<F>(func), std::forward<Args>(args)...),
            delay,
            0,
            1,
            g_engfuncs.pfnTime()
        };
        functions.push_back(f);
    }

    template <typename F, typename... Args>
    void SetInterval(F&& func, float delay, int maxCalls, Args&&... args) {
        ScheduledFunction f = {
            std::bind(std::forward<F>(func), std::forward<Args>(args)...),
            delay,
            0,
            maxCalls,
            g_engfuncs.pfnTime(),
        };
        functions.push_back(f);
    }

    void Think();

private:
    std::vector<ScheduledFunction> functions;
};