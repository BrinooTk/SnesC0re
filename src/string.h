#ifndef EMU_STRING_H
#define EMU_STRING_H

#include <stddef.h>

void *memcpy(void *dst, const void *src, size_t size);
void *memmove(void *dst, const void *src, size_t size);
void *memset(void *dst, int value, size_t size);
int memcmp(const void *a, const void *b, size_t size);

#endif
