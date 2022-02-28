#include <stdint.h>
#include <stddef.h>

// call before doing any crc32_update calls
void crc32_init();

uint32_t crc32_get(const void* buf, size_t len);