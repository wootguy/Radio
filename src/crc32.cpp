#include "crc32.h"

uint32_t crc32_table[256];

void crc32_init()
{
	uint32_t polynomial = 0xEDB88320;
	for (uint32_t i = 0; i < 256; i++)
	{
		uint32_t c = i;
		for (size_t j = 0; j < 8; j++)
		{
			if (c & 1) {
				c = polynomial ^ (c >> 1);
			}
			else {
				c >>= 1;
			}
		}
		crc32_table[i] = c;
	}
}

uint32_t crc32_get(const void* buf, size_t len)
{
	uint32_t c = 0xFFFFFFFF;
	const uint8_t* u = static_cast<const uint8_t*>(buf);
	for (size_t i = 0; i < len; ++i)
	{
		c = crc32_table[(c ^ u[i]) & 0xFF] ^ (c >> 8);
	}
	return c ^ 0xFFFFFFFF;
}