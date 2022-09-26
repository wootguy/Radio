#include "TextMenu.h"
#include "meta_utils.h"

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
void TextMenuClientCommandHook(edict_t* pEntity) {
	if (toLowerCase(CMD_ARGV(0)) == "menuselect") {
		int selection = atoi(CMD_ARGV(1)) - 1;
		if (selection < 0 || selection >= MAX_MENU_OPTIONS) {
			return;
		}

		for (int i = 0; i < MAX_PLAYERS; i++) {
			g_textMenus[i].handleMenuselectCmd(pEntity, selection);
		}
	}
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
		options[i] = "";
	}
	options[MAX_MENU_OPTIONS - 1] = "exit";

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
		if (callback && selection < numOptions) {
			callback(pEntity, selection, options[selection]);
		}
	}
	else {
		println("%s is not viewing the '%s' menu", STRING(pEntity->v.netname), title.c_str());
	}
}

void TextMenu::setTitle(string title) {
	this->title = title;
}

void TextMenu::addOption(string text) {
	if (numOptions >= MAX_MENU_OPTIONS) {
		println("Maximum menu options reached! Failed to add: %s", text.c_str());
		return;
	}

	options[numOptions] = text;

	numOptions++;
}

void TextMenu::openMenu(edict_t* player, int8_t duration) {
	string menuText = title + "\n\n";

	uint16_t validSlots = (1 << 9); // exit option always valid

	for (int i = 0; i < numOptions; i++) {
		menuText += to_string(i+1) + ": " + options[i] + "\n";
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