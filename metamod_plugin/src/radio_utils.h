#pragma once
#include "radio.h"

extern map<string, uint64_t> g_sound_durations; // maps a sound file to its duration in milliseconds

// return existing state or create a new one
PlayerState& getPlayerState(edict_t* plr);

string replaceString(string subject, string search, string replace);

edict_t* getPlayerByUniqueId(string id);

// user IDs change every time a user connects to the server
edict_t* getPlayerByUserId(int id);

string getPlayerUniqueId(edict_t* plr);

bool isValidPlayer(edict_t* plr);

void clientCommand(edict_t* plr, string cmd, int destType = MSG_ONE);

string trimSpaces(string s);

bool cgetline(FILE* file, string& output);

string formatTime(int totalSeconds);

vector<string> splitString(string str, const char* delimitters);

uint32_t getFileSize(FILE* file);

float clampf(float val, float min, float max);

int clamp(int val, int min, int max);

// get the length of a sound file in milliseconds (only .wav supported)
uint64_t getSoundDuration(string fpath);

string getFileExtension(string fpath);