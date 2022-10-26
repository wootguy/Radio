#include "TextMenu.h"
#include "meta_utils.h"
#include "radio_utils.h"

TextMenu g_textMenus[MAX_PLAYERS];

// listen for any other functions/plugins opening menus, so that TextMenu knows if it's the active menu
void TextMenuMessageBeginHook(int msg_dest, int msg_type, const float* pOrigin, edict_t* ed) {
	if (msg_type != MSG_ShowMenu) {
		return;
	}

	for (int i = 0; i < MAX_PLAYERS; i++) {
		g_textMenus[i].handleMenuMessage(msg_dest, ed);
	}
}

// handle player selections
bool TextMenuClientCommandHook(edict_t* pEntity) {
	if (toLowerCase(CMD_ARGV(0)) == "menuselect") {
		int selection = atoi(CMD_ARGV(1)) - 1;
		if (selection < 0 || selection >= MAX_MENU_OPTIONS) {
			return true;
		}

		for (int i = 0; i < MAX_PLAYERS; i++) {
			g_textMenus[i].handleMenuselectCmd(pEntity, selection);
		}

		return true;
	}

	return false;
}

TextMenu& initMenuForPlayer(edict_t* player, TextMenuCallback callback) {
	int idx = player ? ENTINDEX(player) % MAX_PLAYERS : 0;
	TextMenu& menu = g_textMenus[idx];
	menu.init(callback);
	return menu;
}

TextMenu::TextMenu() {
	init(NULL);
}

void TextMenu::init(TextMenuCallback callback) {
	viewers = 0;
	numOptions = 0;

	for (int i = 0; i < MAX_MENU_OPTIONS-1; i++) {
		options[i].displayText = "";
		options[i].data = "";
	}
	TextMenuItem exitItem = { "Exit", "exit" };
	options[MAX_MENU_OPTIONS - 1] = exitItem;

	this->callback = callback;
}

void TextMenu::handleMenuMessage(int msg_dest, edict_t* ed) {

	// Another text menu has been opened for one or more players, so this menu
	// is no longer visible and should not handle menuselect commands

	// If this message is in fact triggered by this object, then the viewer flags should be set
	// after this func finishes.

	if (!viewers) {
		return;
	}

	if ((msg_dest == MSG_ONE || msg_dest == MSG_ONE_UNRELIABLE) && ed) {
		println("New menu opened for %s", STRING(ed->v.netname));
		viewers &= ~(PLAYER_BIT(ed));
	}
	else if (msg_dest == MSG_ALL || msg_dest == MSG_ALL) {
		println("New menu opened for all players");
		viewers = 0;
	}
	else {
		println("Unhandled text menu message dest: %d", msg_dest);
	}
}

void TextMenu::handleMenuselectCmd(edict_t* pEntity, int selection) {
	if (!viewers) {
		return;
	}

	int playerbit = PLAYER_BIT(pEntity);

	if (viewers & playerbit) {
		if (callback && selection < numOptions && isValidPlayer(pEntity)) {
			callback(this, pEntity, selection, options[selection]);
		}
	}
	else {
		println("%s is not viewing the '%s' menu", STRING(pEntity->v.netname), title.c_str());
	}
}

void TextMenu::SetTitle(string title) {
	this->title = title;
}

void TextMenu::AddItem(string displayText, string optionData) {
	if (numOptions >= MAX_MENU_OPTIONS) {
		println("Maximum menu options reached! Failed to add: %s", optionData.c_str());
		return;
	}

	TextMenuItem item = { displayText, optionData };
	options[numOptions] = item;

	numOptions++;
}

void TextMenu::Open(int8_t duration, int8_t page, edict_t* player) {
	string menuText = title + "\n\n";

	uint16_t validSlots = (1 << 9); // exit option always valid

	for (int i = 0; i < numOptions; i++) {
		menuText += to_string(i+1) + ": " + options[i].displayText + "\n";
		validSlots |= (1 << i);
	}

	menuText += "\n0: Exit";

	if (player) {
		MESSAGE_BEGIN(MSG_ONE, MSG_ShowMenu, NULL, player);
		WRITE_SHORT(validSlots);
		WRITE_CHAR(duration);
		WRITE_BYTE(FALSE); // "need more" (?)
		WRITE_STRING(menuText.c_str());
		MESSAGE_END();

		viewers |= PLAYER_BIT(player);
	}
	else {
		MESSAGE_BEGIN(MSG_ALL, MSG_ShowMenu, NULL, player);
		WRITE_SHORT(validSlots);
		WRITE_CHAR(duration);
		WRITE_BYTE(FALSE); // "need more" (?)
		WRITE_STRING(menuText.c_str());
		MESSAGE_END();

		viewers = 0xffffffff;
	}
}