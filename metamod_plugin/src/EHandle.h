#pragma once
#include <extdll.h>
#include "edict.h"
#include "const.h"

class EHandle
{
private:
	edict_t* m_pent;
	int		m_serialnumber;
public:
	EHandle(edict_t* ent);

	edict_t* getEdict();
};