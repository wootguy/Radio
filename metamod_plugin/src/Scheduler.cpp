#include "Scheduler.h"
#include "meta_utils.h"

void Scheduler::Think() {
    float now = g_engfuncs.pfnTime();

    for (int i = 0; i < functions.size(); i++) {
        ScheduledFunction& sched = functions[i];

        if (now - sched.lastCall < sched.delay) {
            continue;
        }

        sched.func();
        sched.lastCall = now;
        sched.callCount++;

        if (sched.maxCalls >= 0 && sched.callCount >= sched.maxCalls) {
            functions.erase(functions.begin() + i);
            i--;
        }
    }
}