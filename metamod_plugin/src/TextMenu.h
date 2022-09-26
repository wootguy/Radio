#include "meta_utils.h"

#define MSG_ShowMenu 93
#define MAX_MENU_OPTIONS 10

typedef void (*TextMenuCallback)(edict_t*, int iSelect, string option);

// this must be called as part of a MessageBegin hook for text menus to know when they are active
void TextMenuMessageBeginHook(int msg_dest, int msg_type, const float* pOrigin, edict_t* ed);

// this must be called as part of a DLL ClientCommand hook for option selections to work
void TextMenuClientCommandHook(edict_t* pEntity);

// Do not create new TextMenus. Only use initMenuForPlayer
class TextMenu {
public:
	TextMenu();

	void init(TextMenuCallback callback);

	void setTitle(string title);
	void addOption(string text);

	// set player to NULL to send to all players.
	// This should be the same target as was used with initMenuForPlayer
	void openMenu(edict_t* player, int8_t duration);

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
	string options[MAX_MENU_OPTIONS];
	int numOptions = 0;
	bool isActive = false;
};


extern TextMenu g_textMenus[MAX_PLAYERS];

// use this to create menus for each player.
// When creating a menu for all players, pass NULL for player.
TextMenu& initMenuForPlayer(edict_t* player, TextMenuCallback callback);