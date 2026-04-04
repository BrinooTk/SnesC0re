#ifndef SNES_RUNTIME_H
#define SNES_RUNTIME_H

#include "core.h"
#include <stddef.h>
#include <stdarg.h>

void snes_runtime_init(void *heap_base, u32 heap_size,
                       void *gadget, void *sendto_fn,
                       s32 log_fd, const u8 *log_sa);
void snes_runtime_reset_heap(void);
void snes_runtime_log(const char *msg);
void snes_runtime_logf(const char *fmt, ...);
void snes_runtime_vlogf(const char *fmt, va_list ap);

#endif
