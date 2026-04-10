#ifndef EMU_SHARED_H
#define EMU_SHARED_H

#include "core.h"

#define MAX_ROMS 4096
#define MAX_NAME 28
#define MAX_ROM_DIR 96

struct rom_entry {
    char filename[48];
    char display[MAX_NAME];
    char source_dir[MAX_ROM_DIR];
};

struct ext_args {
    s64 status;
    s64 step;
    u32 frame_count;
    u32 _pad;
    s32 log_fd;
    s32 pad_fd;
    u8  log_addr[16];
    u64 dbg[8];
};

int  str_len(const char *s);
int  is_rom_file(const char *name);
void extract_rom_name(const char *fn, char *out, int max);

#endif
