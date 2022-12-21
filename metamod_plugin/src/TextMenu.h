#pragma once
#include "meta_utils.h"

#define MSG_ShowMenu 93
#define MAX_MENU_OPTIONS 128
#define ITEMS_PER_PAGE 7

// this must be called as part of a MessageBegin hook for text menus to know when they are active
void TextMenuMessageBeginHook(int msg_dest, int msg_type, const float* pOrigin, edict_t* ed);

// this must be called as part of a DLL ClientCommand hook for option selections to work
bool TextMenuClientCommandHook(edict_t* pEntity);

struct TextMenuItem {
	string displayText;
	string data;
};

typedef void (*TextMenuCallback)(class TextMenu* menu, edict_t* player, int itemNumber, TextMenuItem& item);

// Do not create new TextMenus. Only use initMenuForPlayer
class TextMenu {
public:
	TextMenu();

	void init(TextMenuCallback callback);

	void SetTitle(string title);
	void AddItem(string displayText, string optionData);

	// set player to NULL to send to all players.
	// This should be the same target as was used with initMenuForPlayer
	// paging not supported yet
	void Open(int8_t duration, int8_t page, edict_t* player);

	// don't call directly. This is triggered by global hook functions
	void handleMenuMessage(int msg_dest, edict_t* ed);

	// don't call directly. This is triggered by global hook functions
	void handleMenuselectCmd(edict_t* pEntity, int selection);

private:
	TextMenuCallback callback = NULL;
	int duration = 255; // how long the menu shuold be displayed for
	float openTime = 0; // time when the menu was opened
	uint32_t viewers; // bitfield indicating who can see the menu
	string title;
	TextMenuItem options[MAX_MENU_OPTIONS];
	int numOptions = 0;
	int8_t lastPage = 0;
	int8_t lastDuration = 0;

	bool isActive = false;

	bool isPaginated();
};


extern TextMenu g_textMenus[MAX_PLAYERS];

// use this to create menus for each player.
// When creating a menu for all players, pass NULL for player.
TextMenu& initMenuForPlayer(edict_t* player, TextMenuCallback callback);