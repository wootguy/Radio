#pragma once

// functions to making porting from angelscript to metamod easier
#include <extdll.h>
#include <meta_api.h>

// engine hook table
extern enginefuncs_t g_engine_hooks;

// game dll hook table
extern DLL_FUNCTIONS g_dll_hooks;

void PluginInit();

void PluginExit();
