#include "EHandle.h"
#include <stddef.h>

EHandle::EHandle(edict_t* ent) {
	m_pent = ent;
	m_serialnumber = ent ? m_pent->serialnumber : -1;
}

edict_t* EHandle::getEdict() {
	if (m_pent && m_pent->serialnumber == m_serialnumber) {
		return m_pent;
	}
	return NULL;
};
