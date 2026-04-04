#ifndef EMU_STDIO_H
#define EMU_STDIO_H

#include <stdarg.h>

int printf(const char *fmt, ...);
int vprintf(const char *fmt, va_list ap);

#endif
