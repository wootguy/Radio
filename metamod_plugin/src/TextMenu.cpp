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
		//println("New menu opened for %s", STRING(ed->v.netname));
		viewers &= ~(PLAYER_BIT(ed));
	}
	else if (msg_dest == MSG_ALL || msg_dest == MSG_ALL) {
		//println("New menu opened for all players");
		viewers = 0;
	}
	else {
		//println("Unhandled text menu message dest: %d", msg_dest);
	}
}

void TextMenu::handleMenuselectCmd(edict_t* pEntity, int selection) {
	if (!viewers) {
		return;
	}

	int playerbit = PLAYER_BIT(pEntity);

	if (viewers & playerbit) {
		if (selection == 9) {
			// exit menu
		}
		else if (isPaginated() && selection == 7) {
			Open(lastDuration, lastPage - 1, pEntity);
		}
		else if (isPaginated() && selection == 8) {
			Open(lastDuration, lastPage + 1, pEntity);
		}
		else if (callback && selection < numOptions && isValidPlayer(pEntity)) {
			callback(this, pEntity, selection, options[lastPage*ITEMS_PER_PAGE + selection]);
		}
	}
	else {
		//println("%s is not viewing the '%s' menu", STRING(pEntity->v.netname), title.c_str());
	}
}

bool TextMenu::isPaginated() {
	return numOptions > 9;
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
	if (!isValidPlayer(player)) {
		return;
	}

	string menuText = title + "\n\n";

	uint16_t validSlots = (1 << 9); // exit option always valid

	lastPage = page;
	lastDuration = duration;
	
	int limitPerPage = isPaginated() ? ITEMS_PER_PAGE : 9;
	int itemOffset = page * ITEMS_PER_PAGE;
	int totalPages = (numOptions+6) / ITEMS_PER_PAGE;

	int addedOptions = 0;
	for (int i = itemOffset, k = 0; i < itemOffset+limitPerPage && i < numOptions; i++, k++) {
		menuText += to_string(k+1) + ": " + options[i].displayText + "\n";
		validSlots |= (1 << k);
		addedOptions++;
	}

	while (isPaginated() && addedOptions < ITEMS_PER_PAGE) {
		menuText += "\n";
		addedOptions++;
	}

	menuText += "\n";

	if (isPaginated()) {
		if (page > 0) {
			menuText += "8: Back\n";
			validSlots |= (1 << 7);
		}
		else {
			menuText += "\n";
		}
		if (page < totalPages - 1) {
			menuText += "9: More\n";
			validSlots |= (1 << 8);
		}
		else {
			menuText += "\n";
		}
	}

	menuText += "0: Exit";

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
		println("WARNING: pagination is broken for menus that don't have a destination player");
		MESSAGE_BEGIN(MSG_ALL, MSG_ShowMenu, NULL, player);
		WRITE_SHORT(validSlots);
		WRITE_CHAR(duration);
		WRITE_BYTE(FALSE); // "need more" (?)
		WRITE_STRING(menuText.c_str());
		MESSAGE_END();

		viewers = 0xffffffff;
	}
}