#include "core.h"
#include "ftp.h"
#include "tables.h"
#include "snes/snes.h"

#define MENU_W 256
#define MENU_H 240
#define MENU_SCALE_X 5
#define MENU_SCALE_Y 4
#define MENU_OFF_X ((SCR_W - MENU_W * MENU_SCALE_X) / 2)
#define MENU_OFF_Y ((SCR_H - MENU_H * MENU_SCALE_Y) / 2)

#define SNES_FB_W 512
#define SNES_FB_H 480
#define SNES_SCALE 2
#define SNES_NATIVE_W (SNES_FB_W * SNES_SCALE)
#define SNES_NATIVE_H (SNES_FB_H * SNES_SCALE)
#define SNES_WIDE_W   ((SNES_NATIVE_H * 16) / 9)
#define SNES_OFF_X ((SCR_W - SNES_FB_W * SNES_SCALE) / 2)
#define SNES_OFF_Y ((SCR_H - SNES_FB_H * SNES_SCALE) / 2)
#define SNES_VIDEO_FB_COUNT 3
#define SNES_VIDEO_FB_TOTAL (FB_ALIGNED * SNES_VIDEO_FB_COUNT)

#define SNES_HEAP_SIZE (24 * 1024 * 1024)
#define SNES_ROM_BUF_SIZE (8 * 1024 * 1024)
#define SNES_AUDIO_BUF_SAMPLES 4096
#define SNES_FRAME_SAMPLE_COUNT (960 * 2)
#define SNES_PAD_BUF_SIZE 128
#define SNES_BATTERY_MAX_SIZE 0x20000
#define SNES_AUTOSAVE_FRAMES 300
#define SNES_SAVE_DIR_PRIMARY "/savedata0/brunoroque_snes"
#define SNES_SAVE_DIR_FTP "/av_contents/content_tmp/snes_saves"

#define UI_BG    0
#define UI_BRAND 1
#define UI_HEAD  2
#define UI_LINE  3
#define UI_SEL   4
#define UI_TEXT  5
#define UI_DIM   6
#define UI_CUR   7
#define UI_NUM   8
#define UI_PANEL 9
#define UI_PANEL2 10
#define UI_ACCENT 11
#define UI_BLACK 12

#define BTN_B      0x0001
#define BTN_Y      0x0002
#define BTN_SELECT 0x0004
#define BTN_START  0x0008
#define BTN_UP     0x0010
#define BTN_DOWN   0x0020
#define BTN_LEFT   0x0040
#define BTN_RIGHT  0x0080
#define BTN_A      0x0100
#define BTN_X      0x0200
#define BTN_L      0x0400
#define BTN_R      0x0800
#define BTN_R2     0x1000

static const u32 ui_palette32[] = {
    0xFF191621, 0xFFF05DA8, 0xFFF5F0FF, 0xFFA691C6, 0xFFFF8FCC,
    0xFFF8F5FF, 0xFFC7B8DC, 0xFF73E1FF, 0xFFE2D7F2, 0xFF2A2433,
    0xFF3C334A, 0xFF7B6AFF, 0xFF0A0810
};

struct snes_audio {
    void *gadget;
    void *audio_out_fn;
    s32 audio_handle;
    s16 buf[SNES_AUDIO_BUF_SAMPLES * 2];
    s32 pos;
};

struct snes_host_bundle {
    Snes snes;
    Cpu cpu;
    Apu apu;
    Spc spc;
    Dsp dsp;
    Dma dma;
    Ppu ppu;
    Cart cart;
    Input input1;
    Input input2;
};

static void udp_log(void *G, void *sendto_fn, s32 fd, u8 *sa, const char *msg);
static void diag_log(void *G, void *sendto_fn, s32 log_fd, u8 *log_sa,
                     void *kwrite, s32 diag_fd, const char *msg);
static void clear_fb(u32 *fb);
static u32 align_up_u32(u32 value, u32 alignment);
static int next_fb_index(int active);
static void ui_draw_char(u8 *scr, int x, int y, char ch, u8 color);
static void ui_draw_str(u8 *scr, int x, int y, const char *s, u8 color);
static void ui_draw_centered(u8 *scr, int y, const char *s, u8 color);
static void ui_draw_hline(u8 *scr, int y, int x1, int x2, u8 color);
static void ui_fill_rect(u8 *scr, int x, int y, int w, int h, u8 color);
static void ui_draw_rect(u8 *scr, int x, int y, int w, int h, u8 color);
static void ui_draw_shell(u8 *scr, const char *mode, const char *footer);
static void ui_present_status(void *G, void *vid_flip, void *wait_eq, s32 video, u64 eq,
                              void **fbs, int *active, u32 *total_frames,
                              u8 *scr, const char *title, const char *line1, const char *line2);
static void scale_menu_to_framebuf(u32 *fb, const u8 *scr);
static void scale_snes_to_framebuf(u32 *fb, const u8 *pixels, int widescreen);
static void audio_reset(struct snes_audio *audio, void *G, void *audio_fn, s32 handle);
static void audio_push(struct snes_audio *audio, const s16 *samples, int frames);
static void audio_flush(struct snes_audio *audio);
static Snes *snes_host_init(struct snes_host_bundle *host);
static s32 read_native_pad(void *G, void *pad_read, s32 pad_h, u8 *pbuf, u16 *pad_state, int *action);
static int load_blob_file(void *G, void *kopen, void *kread, void *kclose,
                          const char *path, u8 *buf, int max_size);
static int write_blob_file(void *G, void *kopen, void *kwrite, void *kclose,
                           const char *path, const u8 *buf, int size);
static void ensure_save_dirs(void *G, void *kmkdir);
static void build_save_path(char *out, int max, const char *dir, const char *rom_filename);
static int load_battery_save(void *G, void *kopen, void *kread, void *kclose,
                             Snes *snes, u8 *buf, int max_size,
                             const char *primary_path, const char *ftp_path);
static int flush_battery_save(void *G, void *kopen, void *kwrite, void *kclose,
                              Snes *snes, u8 *buf,
                              const char *primary_path, const char *ftp_path);

int str_len(const char *s) {
    int n = 0;
    while (*s++) n++;
    return n;
}

int is_rom_file(const char *name) {
    int len = str_len(name);
    if (len < 5) return 0;
    char a = name[len - 4], b = name[len - 3], c = name[len - 2], d = name[len - 1];
    if (a != '.') return 0;
    if (b >= 'A' && b <= 'Z') b += 32;
    if (c >= 'A' && c <= 'Z') c += 32;
    if (d >= 'A' && d <= 'Z') d += 32;
    return (b == 's' && c == 'f' && d == 'c') || (b == 's' && c == 'm' && d == 'c');
}

void extract_rom_name(const char *fn, char *out, int max) {
    int i = 0;
    while (fn[i] && fn[i] != '.' && i < max - 1) {
        out[i] = fn[i];
        i++;
    }
    out[i] = 0;
}

static void udp_log(void *G, void *sendto_fn, s32 fd, u8 *sa, const char *msg) {
    if (fd < 0 || !sendto_fn) return;
    NC(G, sendto_fn, (u64)fd, (u64)msg, (u64)str_len(msg), 0, (u64)sa, 16);
}

static void diag_log(void *G, void *sendto_fn, s32 log_fd, u8 *log_sa,
                     void *kwrite, s32 diag_fd, const char *msg) {
    int len = str_len(msg);
    if (log_fd >= 0 && sendto_fn) {
        NC(G, sendto_fn, (u64)log_fd, (u64)msg, (u64)len, 0, (u64)log_sa, 16);
    }
    if (diag_fd >= 0 && kwrite) {
        NC(G, kwrite, (u64)diag_fd, (u64)msg, (u64)len, 0, 0, 0);
    }
}

static void clear_fb(u32 *fb) {
    for (int i = 0; i < SCR_W * SCR_H; i++) fb[i] = 0xFF000000;
}

static u32 align_up_u32(u32 value, u32 alignment) {
    return (value + alignment - 1) & ~(alignment - 1);
}

static int next_fb_index(int active) {
    active++;
    if (active >= SNES_VIDEO_FB_COUNT) active = 0;
    return active;
}

static void ui_draw_char(u8 *scr, int x, int y, char ch, u8 color) {
    int idx = 0;
    if (ch >= 'a' && ch <= 'z') ch -= 32;
    if (ch >= 32 && ch <= 90) idx = ch - 32;
    const u8 *glyph = font_data[idx];
    for (int r = 0; r < 8; r++) {
        u8 bits = glyph[r];
        for (int c = 0; c < 8; c++) {
            if (!(bits & (0x80 >> c))) continue;
            int px = x + c;
            int py = y + r;
            if (px >= 0 && px < MENU_W && py >= 0 && py < MENU_H)
                scr[py * MENU_W + px] = color;
        }
    }
}

static void ui_draw_str(u8 *scr, int x, int y, const char *s, u8 color) {
    while (*s) {
        ui_draw_char(scr, x, y, *s, color);
        x += 8;
        s++;
    }
}

static void ui_draw_centered(u8 *scr, int y, const char *s, u8 color) {
    int x = (MENU_W - str_len(s) * 8) / 2;
    if (x < 0) x = 0;
    ui_draw_str(scr, x, y, s, color);
}

static void ui_draw_hline(u8 *scr, int y, int x1, int x2, u8 color) {
    if (y < 0 || y >= MENU_H) return;
    if (x1 < 0) x1 = 0;
    if (x2 > MENU_W) x2 = MENU_W;
    for (int x = x1; x < x2; x++) scr[y * MENU_W + x] = color;
}

static void ui_fill_rect(u8 *scr, int x, int y, int w, int h, u8 color) {
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > MENU_W) w = MENU_W - x;
    if (y + h > MENU_H) h = MENU_H - y;
    if (w <= 0 || h <= 0) return;
    for (int yy = 0; yy < h; yy++) {
        u8 *row = &scr[(y + yy) * MENU_W + x];
        for (int xx = 0; xx < w; xx++) row[xx] = color;
    }
}

static void ui_draw_rect(u8 *scr, int x, int y, int w, int h, u8 color) {
    if (w <= 1 || h <= 1) return;
    ui_fill_rect(scr, x, y, w, 1, color);
    ui_fill_rect(scr, x, y + h - 1, w, 1, color);
    ui_fill_rect(scr, x, y, 1, h, color);
    ui_fill_rect(scr, x + w - 1, y, 1, h, color);
}

static void ui_draw_shell(u8 *scr, const char *mode, const char *footer) {
    for (int i = 0; i < MENU_W * MENU_H; i++) scr[i] = UI_BG;

    ui_fill_rect(scr, 0, 0, MENU_W, MENU_H, UI_BG);
    for (int band = 0; band < 6; band++) {
        int y = 48 + band * 28;
        ui_fill_rect(scr, 0, y, MENU_W, 12, (band & 1) ? UI_PANEL : UI_PANEL2);
    }

    ui_fill_rect(scr, 0, 0, MENU_W, 18, UI_ACCENT);
    ui_fill_rect(scr, 0, 18, MENU_W, 20, UI_PANEL2);
    ui_fill_rect(scr, 0, MENU_H - 22, MENU_W, 22, UI_PANEL2);

    ui_fill_rect(scr, 10, 48, MENU_W - 20, MENU_H - 78, UI_PANEL);
    ui_draw_rect(scr, 8, 46, MENU_W - 16, MENU_H - 74, UI_LINE);
    ui_draw_rect(scr, 14, 52, MENU_W - 28, MENU_H - 86, UI_PANEL2);

    ui_fill_rect(scr, 16, 12, 56, 12, UI_BRAND);
    ui_draw_centered(scr, 4, "BRUNOROQUE", UI_BLACK);
    ui_draw_centered(scr, 22, "SNESC0RE", UI_HEAD);
    if (mode) ui_draw_centered(scr, 32, mode, UI_DIM);
    if (footer) ui_draw_centered(scr, MENU_H - 14, footer, UI_DIM);
}

static void ui_present_status(void *G, void *vid_flip, void *wait_eq, s32 video, u64 eq,
                              void **fbs, int *active, u32 *total_frames,
                              u8 *scr, const char *title, const char *line1, const char *line2) {
    ui_draw_shell(scr, "SYSTEM STATUS", "CHECK PC LOG WINDOW");
    ui_fill_rect(scr, 28, 88, 200, 64, UI_PANEL2);
    ui_draw_rect(scr, 26, 86, 204, 68, UI_LINE);
    if (title) ui_draw_centered(scr, 98, title, UI_SEL);
    if (line1) ui_draw_centered(scr, 116, line1, UI_TEXT);
    if (line2) ui_draw_centered(scr, 130, line2, UI_DIM);

    scale_menu_to_framebuf((u32 *)fbs[*active], scr);
    NC(G, vid_flip, (u64)video, (u64)*active, 1, *total_frames, 0, 0);
    if (eq && wait_eq) {
        u8 evt[64];
        s32 cnt = 0;
        NC(G, wait_eq, eq, (u64)evt, 1, (u64)&cnt, 0, 0);
    }
    *active = next_fb_index(*active);
    (*total_frames)++;
}

static void scale_menu_to_framebuf(u32 *fb, const u8 *scr) {
    clear_fb(fb);
    for (int y = 0; y < MENU_H; y++) {
        int sy = MENU_OFF_Y + y * MENU_SCALE_Y;
        for (int x = 0; x < MENU_W; x++) {
            u32 color = ui_palette32[scr[y * MENU_W + x] % (sizeof(ui_palette32) / sizeof(ui_palette32[0]))];
            int sx = MENU_OFF_X + x * MENU_SCALE_X;
            for (int dy = 0; dy < MENU_SCALE_Y; dy++) {
                u32 *row = &fb[(sy + dy) * SCR_W + sx];
                for (int dx = 0; dx < MENU_SCALE_X; dx++) row[dx] = color;
            }
        }
    }
}

static void scale_snes_to_framebuf(u32 *fb, const u8 *pixels, int widescreen) {
    int dest_w = widescreen ? SNES_WIDE_W : SNES_NATIVE_W;
    int dest_x = (SCR_W - dest_w) / 2;

    for (int y = 0; y < SNES_FB_H; y++) {
        int sy = SNES_OFF_Y + y * SNES_SCALE;
        // Force a stable progressive image on the PS5 output path.
        // For normal SNES content the emulator already duplicates rows in pairs,
        // so sampling the even row of each pair avoids parity wobble/scanline tremor.
        const u8 *src_row = pixels + (y & ~1) * SNES_FB_W * 4;
        for (int dx = 0; dx < dest_w; dx++) {
            int src_x = widescreen ? (dx * SNES_FB_W) / dest_w : (dx >> 1);
            const u8 *px = src_row + src_x * 4;
            // We request XRGB output from the core, so bytes 0..2 map to B,G,R.
            u32 color = 0xFF000000 | ((u32)px[2] << 16) | ((u32)px[1] << 8) | (u32)px[0];
            int sx = dest_x + dx;
            for (int dy = 0; dy < SNES_SCALE; dy++) {
                fb[(sy + dy) * SCR_W + sx] = color;
            }
        }
    }
}

static void audio_reset(struct snes_audio *audio, void *G, void *audio_fn, s32 handle) {
    audio->gadget = G;
    audio->audio_out_fn = audio_fn;
    audio->audio_handle = handle;
    audio->pos = 0;
    for (int i = 0; i < SNES_AUDIO_BUF_SAMPLES * 2; i++) audio->buf[i] = 0;
}

static void audio_push(struct snes_audio *audio, const s16 *samples, int frames) {
    while (frames > 0 && audio->pos < SNES_AUDIO_BUF_SAMPLES) {
        audio->buf[audio->pos * 2] = samples[0];
        audio->buf[audio->pos * 2 + 1] = samples[1];
        audio->pos++;
        samples += 2;
        frames--;
    }
}

static void audio_flush(struct snes_audio *audio) {
    if (audio->audio_handle < 0 || !audio->audio_out_fn) return;
    while (audio->pos >= SAMPLES_PER_BUF) {
        NC(audio->gadget, audio->audio_out_fn, (u64)audio->audio_handle, (u64)audio->buf, 0, 0, 0, 0);
        int rem = audio->pos - SAMPLES_PER_BUF;
        for (int i = 0; i < rem * 2; i++) audio->buf[i] = audio->buf[SAMPLES_PER_BUF * 2 + i];
        audio->pos = rem;
    }
}

static Snes *snes_host_init(struct snes_host_bundle *host) {
    u8 *raw = (u8 *)host;
    for (u32 i = 0; i < (u32)sizeof(*host); i++) raw[i] = 0;

    Snes *snes = &host->snes;
    snes->cpu = &host->cpu;
    snes->apu = &host->apu;
    snes->dma = &host->dma;
    snes->ppu = &host->ppu;
    snes->cart = &host->cart;
    snes->input1 = &host->input1;
    snes->input2 = &host->input2;
    snes->palTiming = false;

    host->cpu.mem = snes;
    host->cpu.read = snes_cpuRead;
    host->cpu.write = snes_cpuWrite;
    host->cpu.idle = snes_cpuIdle;

    host->apu.snes = snes;
    host->apu.spc = &host->spc;
    host->apu.dsp = &host->dsp;

    host->spc.mem = &host->apu;
    host->spc.read = apu_spcRead;
    host->spc.write = apu_spcWrite;
    host->spc.idle = apu_spcIdle;

    host->dsp.apu = &host->apu;

    host->dma.snes = snes;

    host->ppu.snes = snes;
    ppu_setPixelOutputFormat(&host->ppu, ppu_pixelOutputFormatXBGR);

    host->cart.snes = snes;
    host->cart.type = 0;
    host->cart.ownsRom = false;
    host->cart.rom = 0;
    host->cart.romSize = 0;
    host->cart.ram = 0;
    host->cart.ramSize = 0;

    host->input1.snes = snes;
    host->input1.type = 1;
    host->input2.snes = snes;
    host->input2.type = 1;

    snes_reset(snes, true);
    return snes;
}

static u16 ds_to_snes(u32 raw, int *action) {
    u16 out = 0;
    *action = 0;
    if (raw & 0x00004000) out |= BTN_B;
    if (raw & 0x00008000) out |= BTN_Y;
    if (raw & 0x00000004) out |= BTN_SELECT;
    if (raw & 0x00000100) out |= BTN_SELECT;
    if (raw & 0x00000008) out |= BTN_START;
    if (raw & 0x00000010) out |= BTN_UP;
    if (raw & 0x00000040) out |= BTN_DOWN;
    if (raw & 0x00000080) out |= BTN_LEFT;
    if (raw & 0x00000020) out |= BTN_RIGHT;
    if (raw & 0x00002000) out |= BTN_A;
    if (raw & 0x00001000) out |= BTN_X;
    if (raw & 0x00000400) out |= BTN_L;
    if (raw & 0x00000800) out |= BTN_R;
    if (raw & 0x00000200) out |= BTN_R2;

    if (raw & 0x00000001) *action = 1;
    if (raw & 0x00000002) *action = 2;
    return out;
}

static s32 read_native_pad(void *G, void *pad_read, s32 pad_h, u8 *pbuf, u16 *pad_state, int *action) {
    if (pad_h < 0 || !pad_read) return -1;
    for (int i = 0; i < 128; i++) pbuf[i] = 0;
    s32 n = (s32)NC(G, pad_read, (u64)pad_h, (u64)pbuf, 1, 0, 0, 0);
    if (n <= 0 || (u32)n >= 0x80000000) return -1;
    u32 raw = *(u32 *)pbuf;
    if (raw & 0x80000000) return -1;
    *pad_state = ds_to_snes(raw & 0x001FFFFF, action);
    return 0;
}

static int load_blob_file(void *G, void *kopen, void *kread, void *kclose,
                          const char *path, u8 *buf, int max_size) {
    if (!kopen || !kread || !kclose || !buf) return -1;
    s32 fd = (s32)NC(G, kopen, (u64)path, 0, 0, 0, 0, 0);
    if (fd < 0) return -1;
    int total = 0;
    while (total < max_size) {
        s32 got = (s32)NC(G, kread, (u64)fd, (u64)(buf + total), (u64)(max_size - total), 0, 0, 0);
        if (got <= 0) break;
        total += got;
    }
    NC(G, kclose, (u64)fd, 0, 0, 0, 0, 0);
    return total;
}

static int write_blob_file(void *G, void *kopen, void *kwrite, void *kclose,
                           const char *path, const u8 *buf, int size) {
    if (!kopen || !kwrite || !kclose || !buf || size <= 0) return 0;
    s32 fd = (s32)NC(G, kopen, (u64)path, 0x0601, 0x1FF, 0, 0, 0);
    if (fd < 0) return 0;
    int total = 0;
    while (total < size) {
        s32 wrote = (s32)NC(G, kwrite, (u64)fd, (u64)(buf + total), (u64)(size - total), 0, 0, 0);
        if (wrote <= 0) break;
        total += wrote;
    }
    NC(G, kclose, (u64)fd, 0, 0, 0, 0, 0);
    return total == size;
}

static void ensure_save_dirs(void *G, void *kmkdir) {
    if (!kmkdir) return;
    NC(G, kmkdir, (u64)SNES_SAVE_DIR_PRIMARY, 0x1FF, 0, 0, 0, 0);
    NC(G, kmkdir, (u64)SNES_SAVE_DIR_FTP, 0x1FF, 0, 0, 0, 0);
}

static void build_save_path(char *out, int max, const char *dir, const char *rom_filename) {
    int pos = 0;
    if (!out || max <= 0) return;
    while (*dir && pos < max - 1) out[pos++] = *dir++;
    if (pos < max - 1) out[pos++] = '/';
    while (*rom_filename && pos < max - 5) {
        char ch = *rom_filename++;
        int ok =
            (ch >= 'a' && ch <= 'z') ||
            (ch >= 'A' && ch <= 'Z') ||
            (ch >= '0' && ch <= '9') ||
            ch == ' ' || ch == '.' || ch == '_' || ch == '-' ||
            ch == '(' || ch == ')' || ch == '[' || ch == ']';
        out[pos++] = ok ? ch : '_';
    }
    if (pos == 0) out[pos++] = 'g';
    if (pos < max - 4) out[pos++] = '.';
    if (pos < max - 3) out[pos++] = 's';
    if (pos < max - 2) out[pos++] = 'a';
    if (pos < max - 1) out[pos++] = 'v';
    out[pos] = 0;
}

static int load_battery_save(void *G, void *kopen, void *kread, void *kclose,
                             Snes *snes, u8 *buf, int max_size,
                             const char *primary_path, const char *ftp_path) {
    if (!snes || !snes->cart || snes->cart->ramSize <= 0 || !buf) return 0;
    int size = load_blob_file(G, kopen, kread, kclose, primary_path, buf, max_size);
    if (size <= 0) size = load_blob_file(G, kopen, kread, kclose, ftp_path, buf, max_size);
    if (size <= 0) return 0;
    if (!snes_loadBattery(snes, buf, size)) return -1;
    snes->cart->batteryDirty = false;
    return 1;
}

static int flush_battery_save(void *G, void *kopen, void *kwrite, void *kclose,
                              Snes *snes, u8 *buf,
                              const char *primary_path, const char *ftp_path) {
    if (!snes || !snes->cart || snes->cart->ramSize <= 0 || !buf) return 0;
    int size = snes_saveBattery(snes, buf);
    if (size <= 0) return 0;
    int primary_ok = write_blob_file(G, kopen, kwrite, kclose, primary_path, buf, size);
    int ftp_ok = write_blob_file(G, kopen, kwrite, kclose, ftp_path, buf, size);
    if (primary_ok || ftp_ok) {
        snes->cart->batteryDirty = false;
        return 1;
    }
    return 0;
}

__attribute__((section(".text._start"), force_align_arg_pointer))
void _start(u64 eboot_base, u64 dlsym_addr, struct ext_args *ext) {
    void *G = (void *)(eboot_base + GADGET_OFFSET);
    void *D = (void *)dlsym_addr;
    ext->step = 1;

    void *usleep    = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelUsleep");
    void *cancel    = SYM(G, D, LIBKERNEL_HANDLE, "scePthreadCancel");
    void *load_mod  = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelLoadStartModule");
    void *alloc_dm  = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelAllocateDirectMemory");
    void *map_dm    = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelMapDirectMemory");
    void *dm_size   = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelGetDirectMemorySize");
    void *create_eq = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelCreateEqueue");
    void *wait_eq   = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelWaitEqueue");
    void *delete_eq = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelDeleteEqueue");
    void *mmap      = SYM(G, D, LIBKERNEL_HANDLE, "mmap");
    void *munmap    = SYM(G, D, LIBKERNEL_HANDLE, "munmap");
    void *kopen     = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelOpen");
    void *kread     = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelRead");
    void *kclose    = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelClose");
    void *kwrite    = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelWrite");
    void *kmkdir    = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelMkdir");
    void *recvfrom  = SYM(G, D, LIBKERNEL_HANDLE, "recvfrom");
    void *sendto_fn = SYM(G, D, LIBKERNEL_HANDLE, "sendto");
    void *accept    = SYM(G, D, LIBKERNEL_HANDLE, "accept");
    void *getsockname_fn = SYM(G, D, LIBKERNEL_HANDLE, "getsockname");
    void *getdents  = SYM(G, D, LIBKERNEL_HANDLE, "sceKernelGetdents");
    if (!getdents) getdents = SYM(G, D, LIBKERNEL_HANDLE, "getdents");

    s32 log_fd = ext->log_fd;
    u8 log_sa[16];
    for (int i = 0; i < 16; i++) log_sa[i] = ext->log_addr[i];
    s32 diag_fd = -1;

    s32 userId = (s32)ext->dbg[3];
    s32 ftp_fd = (s32)ext->dbg[4];
    s32 ftp_data_fd = (s32)ext->dbg[5];

    if (!usleep || !load_mod || !mmap) {
        ext->status = -1;
        ext->step = 2;
        return;
    }

    if (kopen) {
        diag_fd = (s32)NC(G, kopen, (u64)"/av_contents/content_tmp/snes_diag.log", 0x0601, 0x1FF, 0, 0, 0);
        if (diag_fd < 0) {
            diag_fd = (s32)NC(G, kopen, (u64)"/savedata0/snes_diag.log", 0x0601, 0x1FF, 0, 0, 0);
        }
    }

    s32 vid_mod = (s32)NC(G, load_mod, (u64)"libSceVideoOut.sprx", 0, 0, 0, 0, 0);
    s32 aud_mod = (s32)NC(G, load_mod, (u64)"libSceAudioOut.sprx", 0, 0, 0, 0, 0);

    void *vid_open  = SYM(G, D, vid_mod, "sceVideoOutOpen");
    void *vid_close = SYM(G, D, vid_mod, "sceVideoOutClose");
    void *vid_reg   = SYM(G, D, vid_mod, "sceVideoOutRegisterBuffers");
    void *vid_flip  = SYM(G, D, vid_mod, "sceVideoOutSubmitFlip");
    void *vid_rate  = SYM(G, D, vid_mod, "sceVideoOutSetFlipRate");
    void *vid_evt   = SYM(G, D, vid_mod, "sceVideoOutAddFlipEvent");
    void *aud_open  = SYM(G, D, aud_mod, "sceAudioOutOpen");
    void *aud_out   = SYM(G, D, aud_mod, "sceAudioOutOutput");
    void *aud_close = SYM(G, D, aud_mod, "sceAudioOutClose");

    if (cancel) {
        u64 gs = *(u64 *)(eboot_base + EBOOT_GS_THREAD);
        if (gs) NC(G, cancel, gs, 0, 0, 0, 0, 0);
    }
    NC(G, usleep, 300000, 0, 0, 0, 0, 0);

    s32 emu_vid = *(s32 *)(eboot_base + EBOOT_VIDOUT);
    if (vid_close && emu_vid >= 0) NC(G, vid_close, (u64)emu_vid, 0, 0, 0, 0, 0);
    NC(G, usleep, 100000, 0, 0, 0, 0, 0);

    s32 video = (s32)NC(G, vid_open, 0xFF, 0, 0, 0, 0, 0);
    if (video < 0) {
        ext->status = -10;
        ext->step = 11;
        return;
    }

    u64 eq = 0;
    if (create_eq) NC(G, create_eq, (u64)&eq, (u64)"snesq", 0, 0, 0, 0);
    if (vid_evt && eq) NC(G, vid_evt, eq, (u64)video, 0, 0, 0, 0);

    u64 mem_total = dm_size ? NC(G, dm_size, 0, 0, 0, 0, 0, 0) : 0x300000000ULL;
    u64 phys = 0;
    NC(G, alloc_dm, 0, mem_total, SNES_VIDEO_FB_TOTAL, 0x200000, 3, (u64)&phys);
    void *vmem = 0;
    NC(G, map_dm, (u64)&vmem, SNES_VIDEO_FB_TOTAL, 0x33, 0, phys, 0x200000);
    if (!vmem) {
        ext->status = -21;
        ext->step = 22;
        return;
    }

    u8 attr[64];
    for (int i = 0; i < 64; i++) attr[i] = 0;
    *(u32 *)(attr + 0) = 0x80000000;
    *(u32 *)(attr + 4) = 1;
    *(u32 *)(attr + 12) = SCR_W;
    *(u32 *)(attr + 16) = SCR_H;
    *(u32 *)(attr + 20) = SCR_W;

    void *fbs[SNES_VIDEO_FB_COUNT];
    fbs[0] = vmem;
    fbs[1] = (u8 *)vmem + FB_ALIGNED;
    fbs[2] = (u8 *)vmem + FB_ALIGNED * 2;

    if (NC(G, vid_reg, (u64)video, 0, (u64)fbs, SNES_VIDEO_FB_COUNT, (u64)attr, 0) != 0) {
        ext->status = -30;
        ext->step = 30;
        return;
    }
    if (vid_rate) NC(G, vid_rate, (u64)video, 0, 0, 0, 0, 0);
    clear_fb((u32 *)fbs[0]);
    clear_fb((u32 *)fbs[1]);
    clear_fb((u32 *)fbs[2]);

    u32 scratch_audio_off = align_up_u32(SNES_PAD_BUF_SIZE, 16);
    u32 scratch_frame_off = align_up_u32(scratch_audio_off + (u32)sizeof(struct snes_audio), 16);
    u32 scratch_battery_off = align_up_u32(scratch_frame_off + (u32)(sizeof(s16) * SNES_FRAME_SAMPLE_COUNT), 16);
    u32 scratch_size = align_up_u32(scratch_battery_off + SNES_BATTERY_MAX_SIZE, 0x1000);

    u8 *menu_scr = (u8 *)NC(G, mmap, 0, MENU_W * MENU_H, 3, 0x1002, (u64)-1, 0);
    if ((s64)menu_scr == -1) {
        ext->status = -40;
        ext->step = 16;
        return;
    }
    ext->step = 17;

    NC(G, load_mod, (u64)"libSceUserService.sprx", 0, 0, 0, 0, 0);
    if (aud_close) for (int h = 0; h < 8; h++) NC(G, aud_close, (u64)h, 0, 0, 0, 0, 0);

    s32 audio_h = -1;
    if (aud_open) audio_h = (s32)NC(G, aud_open, 0xFF, 0, 0, SAMPLES_PER_BUF, SAMPLE_RATE, AUDIO_S16_STEREO);

    s32 pad_mod = (s32)NC(G, load_mod, (u64)"libScePad.sprx", 0, 0, 0, 0, 0);
    void *pad_init_fn = SYM(G, D, pad_mod, "scePadInit");
    void *pad_geth = SYM(G, D, pad_mod, "scePadGetHandle");
    void *pad_read = SYM(G, D, pad_mod, "scePadRead");
    if (pad_init_fn) NC(G, pad_init_fn, 0, 0, 0, 0, 0, 0);
    s32 pad_h = -1;
    if (pad_geth) pad_h = (s32)NC(G, pad_geth, (u64)userId, 0, 0, 0, 0, 0);
    u8 pad_buf[SNES_PAD_BUF_SIZE];
    ext->step = 18;

    diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "BrunoRoque SNES EMU\n");
    diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, pad_h >= 0 ? "Native pad OK\n" : "Native pad N/A\n");

    struct rom_entry *roms = (struct rom_entry *)NC(G, mmap, 0, sizeof(struct rom_entry) * MAX_ROMS, 3, 0x1002, (u64)-1, 0);
    int rom_count = 0;
    const char *rom_dir = ROM_DIR;

    if ((s64)roms != -1) {
        ui_draw_shell(menu_scr, "FTP TRANSFER MODE", "SEND ROMS FROM YOUR PC");
        ui_fill_rect(menu_scr, 24, 92, 208, 54, UI_PANEL2);
        ui_draw_rect(menu_scr, 22, 90, 212, 58, UI_LINE);
        ui_draw_centered(menu_scr, 102, "SNESC0RE IS READY", UI_SEL);
        ui_draw_centered(menu_scr, 118, "FTP SERVER ON PORT 1337", UI_TEXT);
        ui_draw_centered(menu_scr, 132, "WAITING FOR ROMS...", UI_DIM);
        scale_menu_to_framebuf((u32 *)fbs[0], menu_scr);
        scale_menu_to_framebuf((u32 *)fbs[1], menu_scr);
        scale_menu_to_framebuf((u32 *)fbs[2], menu_scr);
        NC(G, vid_flip, (u64)video, 0, 1, 0, 0, 0);

        rom_count = ftp_serve(ftp_fd, ftp_data_fd,
                              G, D, load_mod, mmap, kopen, kread, kwrite, kclose,
                              kmkdir, getdents, usleep, recvfrom, sendto_fn,
                              accept, getsockname_fn,
                              log_fd, log_sa, userId, roms, MAX_ROMS);
        if (rom_count > 0) diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "FTP ROMs loaded\n");
    }

    if (kopen && getdents && (s64)roms != -1) {
        s32 dfd = (s32)NC(G, kopen, (u64)ROM_DIR, 0x20000, 0, 0, 0, 0);
        if (dfd < 0) {
            rom_dir = "/savedata0/";
            dfd = (s32)NC(G, kopen, (u64)"/savedata0/", 0x20000, 0, 0, 0, 0);
        }
        if (dfd >= 0) {
            u8 *dbuf = (u8 *)NC(G, mmap, 0, 0x2000, 3, 0x1002, (u64)-1, 0);
            if ((s64)dbuf != -1) {
                for (;;) {
                    s32 nread = (s32)NC(G, getdents, (u64)dfd, (u64)dbuf, 0x2000, 0, 0, 0);
                    if (nread <= 0) break;
                    int off = 0;
                    while (off < nread && rom_count < MAX_ROMS) {
                        u16 reclen = *(u16 *)(dbuf + off + 4);
                        u8 namlen = *(u8 *)(dbuf + off + 7);
                        char *name = (char *)(dbuf + off + 8);
                        if (reclen == 0) break;
                        if (namlen > 0 && is_rom_file(name)) {
                            int dup = 0;
                            for (int j = 0; j < rom_count; j++) {
                                int match = 1;
                                for (int c = 0; c < 47; c++) {
                                    if (roms[j].filename[c] != name[c]) { match = 0; break; }
                                    if (!name[c]) break;
                                }
                                if (match) { dup = 1; break; }
                            }
                            if (!dup) {
                                int k = 0;
                                while (name[k] && k < 47) { roms[rom_count].filename[k] = name[k]; k++; }
                                roms[rom_count].filename[k] = 0;
                                extract_rom_name(name, roms[rom_count].display, MAX_NAME);
                                rom_count++;
                            }
                        }
                        off += reclen;
                    }
                    if (rom_count >= MAX_ROMS) break;
                }
                if (munmap) NC(G, munmap, (u64)dbuf, 0x2000, 0, 0, 0, 0);
            }
            NC(G, kclose, (u64)dfd, 0, 0, 0, 0, 0);
        }
    }

    u32 total_frames = 0;
    int active = 0;
    for (;;) {
        int selected = 0;
        if (rom_count <= 0) {
            for (int f = 0; f < 300; f++) {
                ui_draw_shell(menu_scr, "LIBRARY EMPTY", "PLACE ROMS IN FTP OR /SAVEDATA0/");
                ui_fill_rect(menu_scr, 28, 92, 200, 54, UI_PANEL2);
                ui_draw_rect(menu_scr, 26, 90, 204, 58, UI_LINE);
                ui_draw_centered(menu_scr, 102, "NO ROMS FOUND", UI_SEL);
                ui_draw_centered(menu_scr, 118, "ADD .SFC OR .SMC FILES", UI_TEXT);
                ui_draw_centered(menu_scr, 132, "THEN REOPEN THE MENU", UI_DIM);
                scale_menu_to_framebuf((u32 *)fbs[active], menu_scr);
                NC(G, vid_flip, (u64)video, (u64)active, 1, (u64)f, 0, 0);
                if (eq && wait_eq) {
                    u8 evt[64];
                    s32 cnt = 0;
                    NC(G, wait_eq, eq, (u64)evt, 1, (u64)&cnt, 0, 0);
                }
                active = next_fb_index(active);
            }
            break;
        }

        {
            int cursor = 0, scroll = 0, mframe = 0, hold = 0;
            u16 prev_btn = 0;
            int require_release = 1;
            int visible = 15;
            if (visible > rom_count) visible = rom_count;

            for (;;) {
                u16 btn = 0;
                int action = 0;
                if (read_native_pad(G, pad_read, pad_h, pad_buf, &btn, &action) < 0) {
                    btn = 0;
                    action = 0;
                }
                if (action == 2) goto done;
                if (require_release) {
                    if (btn == 0) {
                        require_release = 0;
                        prev_btn = 0;
                    } else {
                        btn = 0;
                    }
                }

                u16 pressed = (u16)(btn & ~prev_btn);
                int move = 0;
                if (btn & BTN_UP) {
                    hold++;
                    if ((pressed & BTN_UP) || (hold > 12 && (hold % 4) == 0)) move = -1;
                } else if (btn & BTN_DOWN) {
                    hold++;
                    if ((pressed & BTN_DOWN) || (hold > 12 && (hold % 4) == 0)) move = 1;
                } else {
                    hold = 0;
                }

                if (move) {
                    cursor += move;
                    if (cursor < 0) cursor = rom_count - 1;
                    if (cursor >= rom_count) cursor = 0;
                    if (cursor < scroll) scroll = cursor;
                    if (cursor >= scroll + visible) scroll = cursor - visible + 1;
                }
                if ((pressed & BTN_B) || (pressed & BTN_START)) {
                    selected = cursor;
                    break;
                }

                prev_btn = btn;
                ui_draw_shell(menu_scr, "SNES LIBRARY", "B/START OPEN  R3 EXIT");
                ui_fill_rect(menu_scr, 18, 52, 62, 14, UI_PANEL2);
                ui_draw_rect(menu_scr, 16, 50, 66, 18, UI_LINE);
                ui_draw_str(menu_scr, 24, 55, "ROMS", UI_NUM);
                if (rom_count >= 10) {
                    ui_draw_char(menu_scr, 56, 55, '0' + ((rom_count / 10) % 10), UI_HEAD);
                    ui_draw_char(menu_scr, 64, 55, '0' + (rom_count % 10), UI_HEAD);
                } else {
                    ui_draw_char(menu_scr, 64, 55, '0' + rom_count, UI_HEAD);
                }

                if (scroll > 0) ui_draw_centered(menu_scr, 44, "+", UI_ACCENT);

                int ly = 54;
                for (int i = 0; i < visible && scroll + i < rom_count; i++) {
                    int idx = scroll + i;
                    int iy = ly + i * 10;
                    int sel = (idx == cursor);
                    int num = idx + 1;
                    if (sel) {
                        ui_fill_rect(menu_scr, 18, iy - 1, 220, 10, ((mframe / 10) % 2) ? UI_SEL : UI_BRAND);
                        ui_draw_rect(menu_scr, 16, iy - 2, 224, 12, UI_LINE);
                    }
                    if (sel && ((mframe / 10) % 2)) ui_draw_char(menu_scr, 22, iy, '>', UI_CUR);
                    u8 nc = sel ? UI_BLACK : UI_NUM;
                    int nx = 34;
                    if (rom_count >= 100) { ui_draw_char(menu_scr, nx, iy, '0' + num / 100, nc); nx += 8; }
                    ui_draw_char(menu_scr, nx, iy, '0' + (num / 10) % 10, nc); nx += 8;
                    ui_draw_char(menu_scr, nx, iy, '0' + (num % 10), nc); nx += 8;
                    ui_draw_char(menu_scr, nx, iy, '.', nc); nx += 8;
                    ui_draw_str(menu_scr, nx + 2, iy, roms[idx].display, sel ? UI_BLACK : UI_TEXT);
                }

                if (scroll + visible < rom_count) ui_draw_centered(menu_scr, ly + visible * 10, "+", UI_ACCENT);
                ui_draw_centered(menu_scr, 204, "DOWN+L1+START MENU", UI_DIM);
                ui_draw_centered(menu_scr, 214, "L1+R1+START+R2 WIDE", UI_DIM);

                scale_menu_to_framebuf((u32 *)fbs[active], menu_scr);
                NC(G, vid_flip, (u64)video, (u64)active, 1, total_frames, 0, 0);
                if (eq && wait_eq) {
                    u8 evt[64];
                    s32 cnt = 0;
                    NC(G, wait_eq, eq, (u64)evt, 1, (u64)&cnt, 0, 0);
                }
                active = next_fb_index(active);
                mframe++;
                total_frames++;
            }
        }

        char rom_path[96];
        char save_primary_path[160];
        char save_ftp_path[160];
        {
            int pi = 0;
            const char *p = rom_dir;
            while (*p) rom_path[pi++] = *p++;
            const char *f = roms[selected].filename;
            while (*f && pi < 94) rom_path[pi++] = *f++;
            rom_path[pi] = 0;
            build_save_path(save_primary_path, sizeof(save_primary_path), SNES_SAVE_DIR_PRIMARY, roms[selected].filename);
            build_save_path(save_ftp_path, sizeof(save_ftp_path), SNES_SAVE_DIR_FTP, roms[selected].filename);
        }

        u8 *snes_pixels = (u8 *)-1;
        u8 *rom_file_buf = (u8 *)-1;
        u8 *heap_area = (u8 *)-1;
        u8 *scratch = (u8 *)-1;
        u8 *game_pad_buf = 0;
        u8 *battery_buf = 0;
        struct snes_audio *audio = 0;
        s16 *frame_samples = 0;
        Snes *snes = 0;
        struct snes_host_bundle *host = 0;
        int back_to_menu = 1;
        int want_exit = 0;
        int battery_enabled = 0;

        clear_fb((u32 *)fbs[0]);
        clear_fb((u32 *)fbs[1]);
        clear_fb((u32 *)fbs[2]);
        ext->step = 50;
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES preparing game\n");
        ui_present_status(G, vid_flip, wait_eq, video, eq, fbs, &active, &total_frames,
                          menu_scr, "LOADING GAME", roms[selected].display, "Allocating pixel buffer");

        ext->step = 51;
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES alloc pixels\n");
        snes_pixels = (u8 *)NC(G, mmap, 0, SNES_FB_W * SNES_FB_H * 4, 3, 0x1002, (u64)-1, 0);
        if ((s64)snes_pixels == -1) {
            diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES alloc pixels failed\n");
            goto game_cleanup;
        }

        ext->step = 52;
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES alloc ROM buffer\n");
        ui_present_status(G, vid_flip, wait_eq, video, eq, fbs, &active, &total_frames,
                          menu_scr, "LOADING GAME", roms[selected].display, "Allocating ROM buffer");
        rom_file_buf = (u8 *)NC(G, mmap, 0, SNES_ROM_BUF_SIZE, 3, 0x1002, (u64)-1, 0);
        if ((s64)rom_file_buf == -1) {
            diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES alloc ROM buffer failed\n");
            goto game_cleanup;
        }

        ext->step = 53;
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES alloc heap\n");
        ui_present_status(G, vid_flip, wait_eq, video, eq, fbs, &active, &total_frames,
                          menu_scr, "LOADING GAME", roms[selected].display, "Allocating SNES heap");
        heap_area = (u8 *)NC(G, mmap, 0, SNES_HEAP_SIZE, 3, 0x1002, (u64)-1, 0);
        if ((s64)heap_area == -1) {
            diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES alloc heap failed\n");
            goto game_cleanup;
        }

        ext->step = 54;
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES alloc scratch\n");
        ui_present_status(G, vid_flip, wait_eq, video, eq, fbs, &active, &total_frames,
                          menu_scr, "LOADING GAME", roms[selected].display, "Allocating scratch buffer");
        scratch = (u8 *)NC(G, mmap, 0, scratch_size, 3, 0x1002, (u64)-1, 0);
        if ((s64)scratch == -1) {
            diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES alloc scratch failed\n");
            goto game_cleanup;
        }

        game_pad_buf = scratch;
        audio = (struct snes_audio *)(scratch + scratch_audio_off);
        frame_samples = (s16 *)(scratch + scratch_frame_off);
        battery_buf = scratch + scratch_battery_off;
        for (int i = 0; i < SNES_FB_W * SNES_FB_H * 4; i++) snes_pixels[i] = 0;

        ext->step = 55;
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES audio reset\n");
        audio_reset(audio, G, aud_out, audio_h);

        ext->step = 56;
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES host init\n");
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES host UI begin\n");
        ui_present_status(G, vid_flip, wait_eq, video, eq, fbs, &active, &total_frames,
                          menu_scr, "LOADING GAME", roms[selected].display, "Initializing core state");
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES host UI done\n");
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES host init call\n");
        host = (struct snes_host_bundle *)heap_area;
        snes = snes_host_init(host);
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES host init done\n");

        ext->step = 57;
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES core state ready\n");
        ext->step = 58;
        ui_present_status(G, vid_flip, wait_eq, video, eq, fbs, &active, &total_frames,
                          menu_scr, "LOADING GAME", roms[selected].display, "Reading ROM file");

        {
            int rom_size = load_blob_file(G, kopen, kread, kclose, rom_path, rom_file_buf, SNES_ROM_BUF_SIZE);
            if (rom_size <= 0) {
                diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES ROM read failed\n");
                goto game_cleanup;
            }
            ext->step = 59;
            diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES ROM read OK\n");

            ui_present_status(G, vid_flip, wait_eq, video, eq, fbs, &active, &total_frames,
                              menu_scr, "LOADING GAME", roms[selected].display, "Initializing core");
            if (!snes) {
                diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES core init failed\n");
                goto game_cleanup;
            }
            ext->step = 60;
            diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES core init OK\n");
            snes_setPixelFormat(snes, pixelFormatXRGB);

            ui_present_status(G, vid_flip, wait_eq, video, eq, fbs, &active, &total_frames,
                              menu_scr, "LOADING GAME", roms[selected].display, "Loading cartridge");
            if (!snes_loadRom(snes, rom_file_buf, rom_size)) {
                diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES ROM load failed\n");
                goto game_cleanup;
            }
            ext->step = 61;
            diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES ROM load OK\n");
            battery_enabled = (snes->cart && snes->cart->ramSize > 0);
            if (battery_enabled) {
                int load_result;
                ensure_save_dirs(G, kmkdir);
                ui_present_status(G, vid_flip, wait_eq, video, eq, fbs, &active, &total_frames,
                                  menu_scr, "LOADING GAME", roms[selected].display, "Loading save data");
                load_result = load_battery_save(
                    G, kopen, kread, kclose, snes, battery_buf, SNES_BATTERY_MAX_SIZE,
                    save_primary_path, save_ftp_path
                );
                if (load_result > 0) {
                    diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES battery loaded\n");
                } else if (load_result < 0) {
                    diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES battery load mismatch\n");
                } else {
                    diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES no battery save\n");
                }
            }
        }

        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, rom_path);
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, snes->palTiming ? " PAL\n" : " NTSC\n");

        {
        int pal_acc = 60;
        int debug_combo_latch = 0;
        int widescreen = 0;
        int video_layout_dirty = 0;
        int autosave_counter = 0;
        back_to_menu = 0;
        ext->step = 62;
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES entering frame loop\n");
        for (;;) {
            u16 pad_state = 0;
            int action = 0;
            if (read_native_pad(G, pad_read, pad_h, game_pad_buf, &pad_state, &action) < 0) {
                pad_state = 0;
                action = 0;
            }

            if (action == 2) { want_exit = 1; break; }
            if (action == 1) { back_to_menu = 1; break; }
            if ((pad_state & (BTN_DOWN | BTN_L | BTN_START)) == (BTN_DOWN | BTN_L | BTN_START)) {
                back_to_menu = 1;
                break;
            }
            if ((pad_state & (BTN_L | BTN_R | BTN_START | BTN_R2)) == (BTN_L | BTN_R | BTN_START | BTN_R2)) {
                if (!debug_combo_latch) {
                    widescreen = !widescreen;
                    video_layout_dirty = 1;
                    diag_log(
                        G, sendto_fn, log_fd, log_sa, kwrite, diag_fd,
                        widescreen ? "WIDESCREEN ON\n" : "WIDESCREEN OFF\n"
                    );
                    debug_combo_latch = 1;
                }
            } else if ((pad_state & (BTN_L | BTN_R | BTN_X)) == (BTN_L | BTN_R | BTN_X)) {
                if (!debug_combo_latch) {
                    snes->debugDisableHdma = !snes->debugDisableHdma;
                    diag_log(
                        G, sendto_fn, log_fd, log_sa, kwrite, diag_fd,
                        snes->debugDisableHdma ? "DEBUG HDMA OFF\n" : "DEBUG HDMA ON\n"
                    );
                    debug_combo_latch = 1;
                }
            } else if ((pad_state & (BTN_L | BTN_R | BTN_Y)) == (BTN_L | BTN_R | BTN_Y)) {
                if (!debug_combo_latch) {
                    snes->debugDisableColorMath = !snes->debugDisableColorMath;
                    diag_log(
                        G, sendto_fn, log_fd, log_sa, kwrite, diag_fd,
                        snes->debugDisableColorMath ? "DEBUG COLORMATH OFF\n" : "DEBUG COLORMATH ON\n"
                    );
                    debug_combo_latch = 1;
                }
            } else {
                debug_combo_latch = 0;
            }

            snes_setButtonState(snes, 1, 0, (pad_state & BTN_B) != 0);
            snes_setButtonState(snes, 1, 1, (pad_state & BTN_Y) != 0);
            snes_setButtonState(snes, 1, 2, (pad_state & BTN_SELECT) != 0);
            snes_setButtonState(snes, 1, 3, (pad_state & BTN_START) != 0);
            snes_setButtonState(snes, 1, 4, (pad_state & BTN_UP) != 0);
            snes_setButtonState(snes, 1, 5, (pad_state & BTN_DOWN) != 0);
            snes_setButtonState(snes, 1, 6, (pad_state & BTN_LEFT) != 0);
            snes_setButtonState(snes, 1, 7, (pad_state & BTN_RIGHT) != 0);
            snes_setButtonState(snes, 1, 8, (pad_state & BTN_A) != 0);
            snes_setButtonState(snes, 1, 9, (pad_state & BTN_X) != 0);
            snes_setButtonState(snes, 1, 10, (pad_state & BTN_L) != 0);
            snes_setButtonState(snes, 1, 11, (pad_state & BTN_R) != 0);

            int run_game = 1;
            if (snes->palTiming) {
                pal_acc += 50;
                if (pal_acc >= 60) pal_acc -= 60;
                else run_game = 0;
            }

            if (run_game) {
                int sample_frames = snes->palTiming ? 960 : 800;
                snes_runFrame(snes);
                if (ext->step == 62) {
                    ext->step = 63;
                    diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES first frame CPU OK\n");
                }
                snes_setPixels(snes, snes_pixels);
                if (ext->step == 63) {
                    ext->step = 64;
                    diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES first frame pixels OK\n");
                }
                snes_setSamples(snes, frame_samples, sample_frames);
                if (ext->step == 64) {
                    ext->step = 65;
                    diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES first frame audio mix OK\n");
                }
                audio_push(audio, frame_samples, sample_frames);
            }

            if (battery_enabled && snes->cart->batteryDirty) {
                autosave_counter++;
                if (autosave_counter >= SNES_AUTOSAVE_FRAMES) {
                    if (!flush_battery_save(G, kopen, kwrite, kclose, snes, battery_buf, save_primary_path, save_ftp_path)) {
                        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES battery autosave failed\n");
                    }
                    autosave_counter = 0;
                }
            } else {
                autosave_counter = 0;
            }

            if (video_layout_dirty) {
                clear_fb((u32 *)fbs[0]);
                clear_fb((u32 *)fbs[1]);
                clear_fb((u32 *)fbs[2]);
                video_layout_dirty = 0;
            }

            scale_snes_to_framebuf((u32 *)fbs[active], snes_pixels, widescreen);
            if (ext->step == 65) {
                ext->step = 66;
                diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES first frame blit OK\n");
            }
            NC(G, vid_flip, (u64)video, (u64)active, 1, total_frames, 0, 0);
            audio_flush(audio);
            if (ext->step == 66) {
                ext->step = 67;
                diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES first frame audio out OK\n");
            }

            if (eq && wait_eq) {
                u8 evt[64];
                s32 cnt = 0;
                NC(G, wait_eq, eq, (u64)evt, 1, (u64)&cnt, 0, 0);
            }

            active = next_fb_index(active);
            total_frames++;
            ext->frame_count = total_frames;
        }
        }

game_cleanup:
        if (battery_enabled && snes && snes->cart && snes->cart->batteryDirty) {
            if (flush_battery_save(G, kopen, kwrite, kclose, snes, battery_buf, save_primary_path, save_ftp_path)) {
                diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES battery saved\n");
            } else {
                diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "SNES battery save failed\n");
            }
        }
        if (munmap) {
            if ((s64)scratch != -1) NC(G, munmap, (u64)scratch, scratch_size, 0, 0, 0, 0);
            if ((s64)heap_area != -1) NC(G, munmap, (u64)heap_area, SNES_HEAP_SIZE, 0, 0, 0, 0);
            if ((s64)rom_file_buf != -1) NC(G, munmap, (u64)rom_file_buf, SNES_ROM_BUF_SIZE, 0, 0, 0, 0);
            if ((s64)snes_pixels != -1) NC(G, munmap, (u64)snes_pixels, SNES_FB_W * SNES_FB_H * 4, 0, 0, 0, 0);
        }

        if (want_exit) goto done;
        if (!back_to_menu) break;
    }

done:
    diag_log(G, sendto_fn, log_fd, log_sa, kwrite, diag_fd, "Shutting down...\n");

    if (aud_close && audio_h >= 0) NC(G, aud_close, (u64)audio_h, 0, 0, 0, 0, 0);
    clear_fb((u32 *)fbs[0]);
    clear_fb((u32 *)fbs[1]);
    clear_fb((u32 *)fbs[2]);
    NC(G, vid_flip, (u64)video, (u64)active, 1, total_frames, 0, 0);
    if (usleep) NC(G, usleep, 50000, 0, 0, 0, 0, 0);

    if (vid_close && video >= 0) NC(G, vid_close, (u64)video, 0, 0, 0, 0, 0);
    if (delete_eq && eq) NC(G, delete_eq, eq, 0, 0, 0, 0, 0);
    if (kclose && diag_fd >= 0) NC(G, kclose, (u64)diag_fd, 0, 0, 0, 0, 0);

    if (munmap) {
        if ((s64)menu_scr != -1) NC(G, munmap, (u64)menu_scr, MENU_W * MENU_H, 0, 0, 0, 0);
        if ((s64)roms != -1) NC(G, munmap, (u64)roms, (u64)(sizeof(struct rom_entry) * MAX_ROMS), 0, 0, 0, 0);
    }

    if (diag_fd < 0) {
        udp_log(G, sendto_fn, log_fd, log_sa, "Clean exit\n");
    } else {
        diag_log(G, sendto_fn, log_fd, log_sa, kwrite, -1, "Clean exit\n");
    }
    ext->status = 0;
    ext->step = 99;
    ext->frame_count = total_frames;
}
