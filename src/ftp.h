#ifndef FTP_H
#define FTP_H

#include "emu_shared.h"

#define FTP_PORT      1337
#define FTP_DATA_PORT 1338
#define FTP_DEST      "/av_contents/content_tmp/"
#define FTP_BUF_SZ    8192
#define ROM_DIR       "/av_contents/content_tmp/"

int ftp_serve(s32 srv_fd, s32 data_listen_fd,
              void *G, void *D, void *load_mod, void *mmap,
              void *kopen, void *kread, void *kwrite, void *kclose, void *kmkdir,
              void *getdents, void *usleep,
              void *recvfrom, void *sendto, void *accept,
              void *getsockname,
              s32 log_fd, u8 *log_sa, s32 userId,
              struct rom_entry *roms, int max_roms);

#endif
