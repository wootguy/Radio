#include "TextMenu.h"

using namespace std;

void callbackMenuRadio(TextMenu* menu, edict_t* player, int itemNumber, TextMenuItem& item);
void joinRadioChannel(edict_t* plr, int newChannel);
void callbackMenuChannelSelect(TextMenu* menu, edict_t* player, int itemNumber, TextMenuItem& item);
void callbackMenuRequest(TextMenu* menu, edict_t* player, int itemNumber, TextMenuItem& item);
void callbackMenuEditQueue(TextMenu* menu, edict_t* player, int itemNumber, TextMenuItem& item);
void callbackMenuStopVideo(TextMenu* menu, edict_t* player, int itemNumber, TextMenuItem& item);
void callbackMenuInvite(TextMenu* menu, edict_t* player, int itemNumber, TextMenuItem& item);

void openMenuRadio(int playerid);
void openMenuStopVideo(int playerid);
void openMenuChannelSelect(int playerid);
void openMenuEditQueue(int playerid, int selectedSlot);
void openMenuInviteRequest(int playerid, string asker, int channel);
void openMenuSongRequest(int playerid, string asker, string songName, int channelId);
void openMenuInvite(int playerid);
