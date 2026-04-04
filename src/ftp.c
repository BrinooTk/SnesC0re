#include "ftp.h"

struct ftp_ctx {
    void *G, *D;
    void *kopen, *kread, *kwrite, *kclose, *kmkdir, *getdents;
    void *usleep, *mmap, *munmap, *klseek;
    void *sendto_fn, *recvfrom_fn, *accept_fn;
    void *getsockname_fn, *close_fn;

    /* progress bar */
    void *dlg_init, *dlg_open, *dlg_term;
    void *dlg_set_val, *dlg_set_msg, *dlg_update, *dlg_close;

    s32 log_fd;
    u8 *log_sa;
    s32 userId;

    /* FTP state */
    s32 srv_fd, ctrl_fd, pasv_fd;
    s32 data_listen_fd; /* pre-opened by Lua on port 1338 */
    char cur_path[256];
    int  file_count, total_files;
    int  rom_count;
    u64  total_bytes;

    /* dialog scratch (0x100 bytes) */
    u8  *dlg_buf;
    int  prog_active;

    struct rom_entry *roms;
    int max_roms;
};

static void ftp_log(struct ftp_ctx *f, const char *msg) {
    if (f->log_fd < 0 || !f->sendto_fn) return;
    int len = 0; while (msg[len]) len++;
    NC(f->G, f->sendto_fn, (u64)f->log_fd, (u64)msg, (u64)len, 0, (u64)f->log_sa, 16);
}

static int ftp_startswith(const char *s, const char *prefix) {
    while (*prefix) { if (*s++ != *prefix++) return 0; }
    return 1;
}

static int ftp_atoi(const char *s) {
    int v = 0;
    while (*s >= '0' && *s <= '9') { v = v * 10 + (*s - '0'); s++; }
    return v;
}

static int ftp_itoa(char *buf, int val) {
    if (val == 0) { buf[0] = '0'; buf[1] = 0; return 1; }
    if (val < 0) { buf[0] = '-'; return 1 + ftp_itoa(buf + 1, -val); }
    char tmp[16]; int i = 0;
    while (val > 0) { tmp[i++] = '0' + (val % 10); val /= 10; }
    int len = i;
    for (int j = 0; j < len; j++) buf[j] = tmp[len - 1 - j];
    buf[len] = 0;
    return len;
}

static void ftp_close_fd(struct ftp_ctx *f, s32 fd) {
    if (fd >= 0) NC(f->G, f->close_fn, (u64)fd, 0, 0, 0, 0, 0);
}

static s32 ftp_accept(struct ftp_ctx *f, s32 fd) {
    u8 sa[16]; s32 sa_len = 16;
    return (s32)NC(f->G, f->accept_fn, (u64)fd, (u64)sa, (u64)&sa_len, 0, 0, 0);
}

static s32 ftp_recv(struct ftp_ctx *f, s32 fd, void *buf, s32 len) {
    return (s32)NC(f->G, f->recvfrom_fn, (u64)fd, (u64)buf, (u64)len, 0, 0, 0);
}

static s32 ftp_send(struct ftp_ctx *f, s32 fd, const void *buf, s32 len) {
    return (s32)NC(f->G, f->sendto_fn, (u64)fd, (u64)buf, (u64)len, 0, 0, 0);
}

static void ftp_send_str(struct ftp_ctx *f, s32 fd, const char *s) {
    ftp_send(f, fd, s, str_len(s));
}

static u32 ftp_get_ip(struct ftp_ctx *f, s32 fd) {
    u8 sa[16] = {0}; s32 len = 16;
    NC(f->G, f->getsockname_fn, (u64)fd, (u64)sa, (u64)&len, 0, 0, 0);
    return *(u32*)(sa + 4);
}

static void prog_open(struct ftp_ctx *f, const char *msg, int total) {
    f->total_files = total;
    f->file_count = 0;
    f->total_bytes = 0;
    f->prog_active = 0;

    if (!f->dlg_init || !f->dlg_open || !f->dlg_term) return;
    NC(f->G, f->dlg_term, 0, 0, 0, 0, 0, 0);
    NC(f->G, f->dlg_init, 0, 0, 0, 0, 0, 0);

    u8 *dp = f->dlg_buf;
    u8 *pp = f->dlg_buf + 0x88;
    for (int i = 0; i < 0x100; i++) dp[i] = 0;
    for (int i = 0; i < 0x50; i++) pp[i] = 0;

    u32 magic = (u32)((u64)dp + 0xC0D1A109);
    *(u64*)(dp + 0x00) = 0x30;
    *(u32*)(dp + 0x2C) = magic;
    *(u64*)(dp + 0x30) = 0x88;
    *(u32*)(dp + 0x38) = 2; /* PROGRESS_BAR */
    *(u64*)(dp + 0x48) = (u64)pp;
    *(u32*)(dp + 0x58) = (u32)f->userId;
    *(u32*)(pp + 0x00) = 0; /* PERCENTAGE */

    char *mbuf = (char *)(f->dlg_buf + 0xE0);
    int mlen = str_len(msg);
    for (int i = 0; i < mlen && i < 60; i++) mbuf[i] = msg[i];
    mbuf[mlen < 60 ? mlen : 60] = 0;
    *(u64*)(pp + 0x08) = (u64)mbuf;

    s32 ret = (s32)NC(f->G, f->dlg_open, (u64)dp, 0, 0, 0, 0, 0);
    f->prog_active = (ret == 0);
}

static void prog_set(struct ftp_ctx *f, int pct, const char *msg) {
    if (!f->prog_active) return;
    if (f->dlg_update) NC(f->G, f->dlg_update, 0, 0, 0, 0, 0, 0);
    if (f->dlg_set_val) NC(f->G, f->dlg_set_val, 0, (u64)pct, 0, 0, 0, 0);
    if (msg && f->dlg_set_msg) {
        char *mbuf = (char *)(f->dlg_buf + 0xE0);
        int mlen = str_len(msg);
        for (int i = 0; i < mlen && i < 60; i++) mbuf[i] = msg[i];
        mbuf[mlen < 60 ? mlen : 60] = 0;
        NC(f->G, f->dlg_set_msg, 0, (u64)mbuf, 0, 0, 0, 0);
    }
}

static void prog_done(struct ftp_ctx *f) {
    if (!f->prog_active) return;
    char msg[64]; int p = 0;
    const char *pfx = "Done! "; while (*pfx) msg[p++] = *pfx++;
    p += ftp_itoa(msg + p, f->file_count);
    const char *sfx = " files"; while (*sfx) msg[p++] = *sfx++;
    msg[p] = 0;
    prog_set(f, 100, msg);
    NC(f->G, f->usleep, 2000000, 0, 0, 0, 0, 0);
    if (f->dlg_close) NC(f->G, f->dlg_close, 0, 0, 0, 0, 0, 0);
    if (f->dlg_update) {
        for (int i = 0; i < 20; i++) {
            if ((s32)NC(f->G, f->dlg_update, 0, 0, 0, 0, 0, 0) == 0) break;
            NC(f->G, f->usleep, 100000, 0, 0, 0, 0, 0);
        }
    }
    f->prog_active = 0;
    if (f->dlg_term) NC(f->G, f->dlg_term, 0, 0, 0, 0, 0, 0);
}

static s32 open_pasv(struct ftp_ctx *f) {
    u32 ip = ftp_get_ip(f, f->ctrl_fd);
    u8 a = ip & 0xFF, b = (ip >> 8) & 0xFF;
    u8 c = (ip >> 16) & 0xFF, d = (ip >> 24) & 0xFF;
    u8 plo = FTP_DATA_PORT & 0xFF;
    u8 phi = (FTP_DATA_PORT >> 8) & 0xFF;

    char resp[80];
    int n = 0;
    const char *h = "227 Entering Passive Mode (";
    while (*h) resp[n++] = *h++;
    n += ftp_itoa(resp + n, a); resp[n++] = ',';
    n += ftp_itoa(resp + n, b); resp[n++] = ',';
    n += ftp_itoa(resp + n, c); resp[n++] = ',';
    n += ftp_itoa(resp + n, d); resp[n++] = ',';
    n += ftp_itoa(resp + n, phi); resp[n++] = ',';
    n += ftp_itoa(resp + n, plo);
    resp[n++] = ')'; resp[n++] = '\r'; resp[n++] = '\n'; resp[n] = 0;
    ftp_send_str(f, f->ctrl_fd, resp);
    return 0;
}

static s32 accept_data(struct ftp_ctx *f) {
    f->pasv_fd = ftp_accept(f, f->data_listen_fd);
    return f->pasv_fd;
}

static void close_data(struct ftp_ctx *f) {
    ftp_close_fd(f, f->pasv_fd); f->pasv_fd = -1;
}

static const char *basename_of(const char *path) {
    const char *last = path;
    for (const char *p = path; *p; p++)
        if (*p == '/') last = p + 1;
    return last;
}

static void cmd_stor(struct ftp_ctx *f, const char *arg) {
    char path[256];
    int pi = 0;
    const char *base = FTP_DEST;
    while (*base) path[pi++] = *base++;
    const char *fn = basename_of(arg);
    int fnlen = str_len(fn);
    for (int i = 0; i < fnlen && pi < 254; i++) path[pi++] = fn[i];
    path[pi] = 0;

    s32 fd = (s32)NC(f->G, f->kopen, (u64)path, 0x0601, 0x1FF, 0, 0, 0);
    if (fd < 0) {
        ftp_send_str(f, f->ctrl_fd, "550 Cannot create file\r\n");
        return;
    }

    accept_data(f);
    ftp_send_str(f, f->ctrl_fd, "150 Opening data connection\r\n");

    u8 *buf = (u8 *)NC(f->G, f->mmap, 0, FTP_BUF_SZ, 3, 0x1002, (u64)-1, 0);
    u64 file_bytes = 0;

    for (;;) {
        s32 n = ftp_recv(f, f->pasv_fd, buf, FTP_BUF_SZ);
        if (n <= 0) break;
        NC(f->G, f->kwrite, (u64)fd, (u64)buf, (u64)n, 0, 0, 0);
        file_bytes += n;
    }

    NC(f->G, f->kclose, (u64)fd, 0, 0, 0, 0, 0);
    if (f->munmap) NC(f->G, f->munmap, (u64)buf, FTP_BUF_SZ, 0, 0, 0, 0);

    ftp_send_str(f, f->ctrl_fd, "226 Transfer complete\r\n");
    close_data(f);

    f->file_count++;
    f->total_bytes += file_bytes;

    if (is_rom_file(fn) && f->roms && f->rom_count < f->max_roms) {
        struct rom_entry *r = &f->roms[f->rom_count];
        int k = 0;
        while (fn[k] && k < 47) { r->filename[k] = fn[k]; k++; }
        r->filename[k] = 0;
        k = 0;
        for (int i = 0; fn[i] && fn[i] != '.' && k < MAX_NAME - 1; i++)
            r->display[k++] = fn[i];
        r->display[k] = 0;
        f->rom_count++;
    }

    if (f->prog_active && f->total_files > 0) {
        int pct = (f->file_count * 100) / f->total_files;
        if (pct > 99) pct = 99;
        char pmsg[64]; int p = 0;
        const char *c = "Copying: "; while (*c) pmsg[p++] = *c++;
        p += ftp_itoa(pmsg + p, f->file_count);
        pmsg[p++] = '/';
        p += ftp_itoa(pmsg + p, f->total_files);
        pmsg[p] = 0;
        prog_set(f, pct, pmsg);
    }
}

static void cmd_retr(struct ftp_ctx *f, const char *arg) {
    char path[256];
    int pi = 0;
    const char *base = FTP_DEST;
    while (*base) path[pi++] = *base++;
    const char *fn = basename_of(arg);
    int fnlen = str_len(fn);
    for (int i = 0; i < fnlen && pi < 254; i++) path[pi++] = fn[i];
    path[pi] = 0;

    s32 fd = (s32)NC(f->G, f->kopen, (u64)path, 0, 0, 0, 0, 0);
    if (fd < 0) {
        ftp_send_str(f, f->ctrl_fd, "550 File not found\r\n");
        return;
    }

    if (accept_data(f) < 0) {
        NC(f->G, f->kclose, (u64)fd, 0, 0, 0, 0, 0);
        ftp_send_str(f, f->ctrl_fd, "425 Cannot open data connection\r\n");
        return;
    }

    ftp_send_str(f, f->ctrl_fd, "150 Opening data connection\r\n");

    u8 *buf = (u8 *)NC(f->G, f->mmap, 0, FTP_BUF_SZ, 3, 0x1002, (u64)-1, 0);
    if ((s64)buf == -1) {
        NC(f->G, f->kclose, (u64)fd, 0, 0, 0, 0, 0);
        close_data(f);
        ftp_send_str(f, f->ctrl_fd, "451 Local error\r\n");
        return;
    }

    for (;;) {
        s32 n = (s32)NC(f->G, f->kread, (u64)fd, (u64)buf, FTP_BUF_SZ, 0, 0, 0);
        if (n <= 0) break;
        s32 sent = ftp_send(f, f->pasv_fd, buf, n);
        if (sent <= 0) break;
    }

    NC(f->G, f->kclose, (u64)fd, 0, 0, 0, 0, 0);
    if (f->munmap) NC(f->G, f->munmap, (u64)buf, FTP_BUF_SZ, 0, 0, 0, 0);

    ftp_send_str(f, f->ctrl_fd, "226 Transfer complete\r\n");
    close_data(f);
}

static void cmd_size(struct ftp_ctx *f, const char *arg) {
    char path[256]; int pi = 0;
    const char *base = FTP_DEST;
    while (*base) path[pi++] = *base++;
    const char *fn = basename_of(arg);
    while (*fn && pi < 254) path[pi++] = *fn++;
    path[pi] = 0;

    s32 fd = (s32)NC(f->G, f->kopen, (u64)path, 0, 0, 0, 0, 0);
    if (fd < 0) {
        ftp_send_str(f, f->ctrl_fd, "550 File not found\r\n");
        return;
    }
    s64 sz = 0;
    if (f->klseek) sz = (s64)NC(f->G, f->klseek, (u64)fd, 0, 2, 0, 0, 0);
    NC(f->G, f->kclose, (u64)fd, 0, 0, 0, 0, 0);

    char resp[64];
    int n = 0;
    const char *h = "213 "; while (*h) resp[n++] = *h++;
    n += ftp_itoa(resp + n, (int)sz);
    resp[n++] = '\r'; resp[n++] = '\n'; resp[n] = 0;
    ftp_send_str(f, f->ctrl_fd, resp);
}

static void cmd_nlst(struct ftp_ctx *f) {
    accept_data(f);
    ftp_send_str(f, f->ctrl_fd, "150 Opening data connection\r\n");

    s32 dfd = (s32)NC(f->G, f->kopen, (u64)FTP_DEST, 0x20000, 0, 0, 0, 0);
    if (dfd >= 0 && f->getdents) {
        u8 *dbuf = (u8 *)NC(f->G, f->mmap, 0, 4096, 3, 0x1002, (u64)-1, 0);
        if ((s64)dbuf != -1) {
            for (;;) {
                s32 nread = (s32)NC(f->G, f->getdents, (u64)dfd, (u64)dbuf, 4096, 0, 0, 0);
                if (nread <= 0) break;
                int off = 0;
                while (off < nread) {
                    u16 reclen = *(u16*)(dbuf + off + 4);
                    if (reclen == 0) break;
                    char *name = (char *)(dbuf + off + 8);
                    if (name[0] != '.') {
                        ftp_send_str(f, f->pasv_fd, name);
                        ftp_send(f, f->pasv_fd, "\r\n", 2);
                    }
                    off += reclen;
                }
            }
            if (f->munmap) NC(f->G, f->munmap, (u64)dbuf, 4096, 0, 0, 0, 0);
        }
        NC(f->G, f->kclose, (u64)dfd, 0, 0, 0, 0, 0);
    }

    ftp_send_str(f, f->ctrl_fd, "226 Transfer complete\r\n");
    close_data(f);
}

static int ftp_handle_cmd(struct ftp_ctx *f, char *line) {
    int len = str_len(line);
    while (len > 0 && (line[len-1] == '\r' || line[len-1] == '\n')) line[--len] = 0;

    char *arg = 0;
    for (int i = 0; i < len; i++) {
        if (line[i] == ' ') { line[i] = 0; arg = line + i + 1; break; }
    }

    if (ftp_startswith(line, "USER")) {
        ftp_send_str(f, f->ctrl_fd, "331 OK\r\n");
    } else if (ftp_startswith(line, "PASS")) {
        ftp_send_str(f, f->ctrl_fd, "230 OK\r\n");
    } else if (ftp_startswith(line, "SYST")) {
        ftp_send_str(f, f->ctrl_fd, "215 UNIX Type: L8\r\n");
    } else if (ftp_startswith(line, "FEAT")) {
        ftp_send_str(f, f->ctrl_fd, "211-extensions\r\nREST STREAM\r\n211 end\r\n");
    } else if (ftp_startswith(line, "TYPE")) {
        ftp_send_str(f, f->ctrl_fd, "200 OK\r\n");
    } else if (ftp_startswith(line, "PWD")) {
        ftp_send_str(f, f->ctrl_fd, "257 \"/av_contents/content_tmp\"\r\n");
    } else if (ftp_startswith(line, "CWD")) {
        ftp_send_str(f, f->ctrl_fd, "250 OK\r\n");
    } else if (ftp_startswith(line, "PASV")) {
        open_pasv(f);
    } else if (ftp_startswith(line, "STOR") && arg) {
        cmd_stor(f, arg);
    } else if (ftp_startswith(line, "RETR") && arg) {
        cmd_retr(f, arg);
    } else if (ftp_startswith(line, "SIZE") && arg) {
        cmd_size(f, arg);
    } else if (ftp_startswith(line, "NLST")) {
        cmd_nlst(f);
    } else if (ftp_startswith(line, "LIST")) {
        cmd_nlst(f);
    } else if (ftp_startswith(line, "NOOP")) {
        ftp_send_str(f, f->ctrl_fd, "200 OK\r\n");
    } else if (ftp_startswith(line, "REST")) {
        ftp_send_str(f, f->ctrl_fd, "350 OK\r\n");
    } else if (ftp_startswith(line, "MKD")) {
        ftp_send_str(f, f->ctrl_fd, "257 OK\r\n");
    } else if (ftp_startswith(line, "SITE")) {
        if (arg && ftp_startswith(arg, "TOTAL ")) {
            int total = ftp_atoi(arg + 6);
            char msg[64]; int p = 0;
            const char *c = "Preparing to copy "; while (*c) msg[p++] = *c++;
            p += ftp_itoa(msg + p, total);
            const char *s = " files..."; while (*s) msg[p++] = *s++;
            msg[p] = 0;
            prog_open(f, msg, total);
            ftp_send_str(f, f->ctrl_fd, "200 OK\r\n");
        } else if (arg && ftp_startswith(arg, "EXIT")) {
            prog_done(f);
            ftp_send_str(f, f->ctrl_fd, "221 Bye\r\n");
            return 1; /* exit signal */
        } else {
            ftp_send_str(f, f->ctrl_fd, "200 OK\r\n");
        }
    } else if (ftp_startswith(line, "QUIT")) {
        ftp_send_str(f, f->ctrl_fd, "221 Bye\r\n");
        return -1; /* disconnect */
    } else {
        ftp_send_str(f, f->ctrl_fd, "500 Unknown\r\n");
    }
    return 0;
}

int ftp_serve(s32 srv_fd, s32 data_listen_fd,
              void *G, void *D, void *load_mod, void *mmap,
              void *kopen, void *kread, void *kwrite, void *kclose, void *kmkdir,
              void *getdents, void *usleep,
              void *recvfrom, void *sendto, void *accept,
              void *getsockname,
              s32 log_fd, u8 *log_sa, s32 userId,
              struct rom_entry *roms, int max_roms) {

    struct ftp_ctx f;
    u8 *p = (u8*)&f; for (u32 i = 0; i < sizeof(f); i++) p[i] = 0;

    f.G = G; f.D = D;
    f.kopen = kopen; f.kread = kread; f.kwrite = kwrite; f.kclose = kclose;
    f.kmkdir = kmkdir; f.getdents = getdents;
    f.usleep = usleep; f.mmap = mmap;
    f.sendto_fn = sendto; f.recvfrom_fn = recvfrom;
    f.accept_fn = accept;
    f.getsockname_fn = getsockname;
    f.log_fd = log_fd; f.log_sa = log_sa;
    f.userId = userId;
    f.roms = roms; f.max_roms = max_roms;
    f.srv_fd = srv_fd;
    f.data_listen_fd = data_listen_fd;
    f.ctrl_fd = -1; f.pasv_fd = -1;

    f.close_fn = SYM(G, D, LIBKERNEL_HANDLE, "close");
    f.munmap   = SYM(G, D, LIBKERNEL_HANDLE, "munmap");
    f.klseek   = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelLseek");

    s32 dlg_mod = (s32)NC(G, load_mod, (u64)"libSceMsgDialog.sprx", 0, 0, 0, 0, 0);
    if (dlg_mod > 0) {
        f.dlg_init    = SYM(G, D, dlg_mod, "sceMsgDialogInitialize");
        f.dlg_open    = SYM(G, D, dlg_mod, "sceMsgDialogOpen");
        f.dlg_term    = SYM(G, D, dlg_mod, "sceMsgDialogTerminate");
        f.dlg_set_val = SYM(G, D, dlg_mod, "sceMsgDialogProgressBarSetValue");
        f.dlg_set_msg = SYM(G, D, dlg_mod, "sceMsgDialogProgressBarSetMsg");
        f.dlg_update  = SYM(G, D, dlg_mod, "sceMsgDialogUpdateStatus");
        f.dlg_close   = SYM(G, D, dlg_mod, "sceMsgDialogClose");
    }

    f.dlg_buf = (u8*)NC(G, mmap, 0, 0x200, 3, 0x1002, (u64)-1, 0);

    if (srv_fd < 0) { ftp_log(&f, "FTP: no server socket\n"); return 0; }
    if (data_listen_fd < 0) { ftp_log(&f, "FTP: no data socket\n"); return 0; }

    ftp_log(&f, "FTP: listening on 1337\n");

    int exit_flag = 0;
    char cmd_buf[512];

    while (!exit_flag) {
        f.ctrl_fd = ftp_accept(&f, f.srv_fd);
        if (f.ctrl_fd < 0) continue;

        ftp_log(&f, "FTP: client\n");
        ftp_send_str(&f, f.ctrl_fd, "220 EgyDev FTP\r\n");

        while (!exit_flag) {
            s32 n = ftp_recv(&f, f.ctrl_fd, cmd_buf, 510);
            if (n <= 0) break;
            cmd_buf[n] = 0;

            int ret = ftp_handle_cmd(&f, cmd_buf);
            if (ret == 1) { exit_flag = 1; break; }
            if (ret == -1) break;
        }

        ftp_close_fd(&f, f.ctrl_fd);
        f.ctrl_fd = -1;
    }

    ftp_close_fd(&f, f.ctrl_fd);
    ftp_close_fd(&f, f.pasv_fd);
    ftp_close_fd(&f, f.srv_fd);
    ftp_close_fd(&f, f.data_listen_fd);
    if (f.munmap && f.dlg_buf)
        NC(f.G, f.munmap, (u64)f.dlg_buf, 0x200, 0, 0, 0, 0);
    ftp_log(&f, "FTP: stopped\n");
    return f.rom_count;
}
