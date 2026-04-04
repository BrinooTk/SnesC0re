#include "snes_runtime.h"
#include "string.h"

typedef struct alloc_hdr {
    u32 size;
    u32 reserved;
} alloc_hdr;

static u8 *g_heap_base;
static u8 *g_heap_ptr;
static u8 *g_heap_end;
static void *g_gadget;
static void *g_sendto_fn;
static s32 g_log_fd = -1;
static u8 g_log_sa[16];

static u32 align16(u32 value) {
    return (value + 15U) & ~15U;
}

static int min_int(int a, int b) {
    return a < b ? a : b;
}

void snes_runtime_init(void *heap_base, u32 heap_size,
                       void *gadget, void *sendto_fn,
                       s32 log_fd, const u8 *log_sa) {
    g_heap_base = (u8 *)heap_base;
    g_heap_ptr = g_heap_base;
    g_heap_end = g_heap_base + heap_size;
    g_gadget = gadget;
    g_sendto_fn = sendto_fn;
    g_log_fd = log_fd;
    for (int i = 0; i < 16; i++) g_log_sa[i] = log_sa ? log_sa[i] : 0;
}

void snes_runtime_reset_heap(void) {
    g_heap_ptr = g_heap_base;
}

void *malloc(size_t size) {
    if (!g_heap_ptr || size == 0) return 0;
    u32 total = align16((u32)size + (u32)sizeof(alloc_hdr));
    if (g_heap_ptr + total > g_heap_end) return 0;
    alloc_hdr *hdr = (alloc_hdr *)g_heap_ptr;
    hdr->size = (u32)size;
    hdr->reserved = 0;
    g_heap_ptr += total;
    return (void *)(hdr + 1);
}

void free(void *ptr) {
    (void)ptr;
}

void *realloc(void *ptr, size_t size) {
    if (!ptr) return malloc(size);
    if (size == 0) {
        free(ptr);
        return 0;
    }
    alloc_hdr *hdr = ((alloc_hdr *)ptr) - 1;
    void *new_ptr = malloc(size);
    if (!new_ptr) return 0;
    memcpy(new_ptr, ptr, (size_t)min_int((int)hdr->size, (int)size));
    return new_ptr;
}

void *memcpy(void *dst, const void *src, size_t size) {
    u8 *d = (u8 *)dst;
    const u8 *s = (const u8 *)src;
    for (size_t i = 0; i < size; i++) d[i] = s[i];
    return dst;
}

void *memmove(void *dst, const void *src, size_t size) {
    u8 *d = (u8 *)dst;
    const u8 *s = (const u8 *)src;
    if (d == s || size == 0) return dst;
    if (d < s) {
        for (size_t i = 0; i < size; i++) d[i] = s[i];
    } else {
        for (size_t i = size; i > 0; i--) d[i - 1] = s[i - 1];
    }
    return dst;
}

void *memset(void *dst, int value, size_t size) {
    u8 *d = (u8 *)dst;
    u8 v = (u8)value;
    for (size_t i = 0; i < size; i++) d[i] = v;
    return dst;
}

int memcmp(const void *a, const void *b, size_t size) {
    const u8 *aa = (const u8 *)a;
    const u8 *bb = (const u8 *)b;
    for (size_t i = 0; i < size; i++) {
        if (aa[i] != bb[i]) return (int)aa[i] - (int)bb[i];
    }
    return 0;
}

void snes_runtime_log(const char *msg) {
    if (!msg || g_log_fd < 0 || !g_sendto_fn) return;
    int len = 0;
    while (msg[len]) len++;
    NC(g_gadget, g_sendto_fn, (u64)g_log_fd, (u64)msg, (u64)len, 0, (u64)g_log_sa, 16);
}

static int append_char(char *buf, int pos, int max, char ch) {
    if (pos < max - 1) buf[pos] = ch;
    return pos + 1;
}

static int append_str(char *buf, int pos, int max, const char *str) {
    const char *s = str ? str : "(null)";
    while (*s) {
        pos = append_char(buf, pos, max, *s);
        s++;
    }
    return pos;
}

static int append_u32_base(char *buf, int pos, int max, u32 value, u32 base, int upper) {
    char tmp[16];
    int n = 0;
    if (value == 0) return append_char(buf, pos, max, '0');
    while (value && n < (int)sizeof(tmp)) {
        u32 digit = value % base;
        tmp[n++] = (char)(digit < 10 ? ('0' + digit) : ((upper ? 'A' : 'a') + (digit - 10)));
        value /= base;
    }
    while (n > 0) pos = append_char(buf, pos, max, tmp[--n]);
    return pos;
}

static int append_s32(char *buf, int pos, int max, s32 value) {
    if (value < 0) {
        pos = append_char(buf, pos, max, '-');
        return append_u32_base(buf, pos, max, (u32)(-value), 10, 0);
    }
    return append_u32_base(buf, pos, max, (u32)value, 10, 0);
}

void snes_runtime_vlogf(const char *fmt, va_list ap) {
    char buf[512];
    int pos = 0;
    for (const char *p = fmt; *p; p++) {
        if (*p != '%') {
            pos = append_char(buf, pos, (int)sizeof(buf), *p);
            continue;
        }
        p++;
        if (!*p) break;
        switch (*p) {
        case '%':
            pos = append_char(buf, pos, (int)sizeof(buf), '%');
            break;
        case 'c':
            pos = append_char(buf, pos, (int)sizeof(buf), (char)va_arg(ap, int));
            break;
        case 's':
            pos = append_str(buf, pos, (int)sizeof(buf), va_arg(ap, const char *));
            break;
        case 'd':
        case 'i':
            pos = append_s32(buf, pos, (int)sizeof(buf), va_arg(ap, int));
            break;
        case 'u':
            pos = append_u32_base(buf, pos, (int)sizeof(buf), va_arg(ap, unsigned int), 10, 0);
            break;
        case 'x':
            pos = append_u32_base(buf, pos, (int)sizeof(buf), va_arg(ap, unsigned int), 16, 0);
            break;
        case 'X':
            pos = append_u32_base(buf, pos, (int)sizeof(buf), va_arg(ap, unsigned int), 16, 1);
            break;
        default:
            pos = append_char(buf, pos, (int)sizeof(buf), '%');
            pos = append_char(buf, pos, (int)sizeof(buf), *p);
            break;
        }
    }
    if (pos >= (int)sizeof(buf)) pos = (int)sizeof(buf) - 1;
    buf[pos] = 0;
    snes_runtime_log(buf);
}

void snes_runtime_logf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    snes_runtime_vlogf(fmt, ap);
    va_end(ap);
}

int vprintf(const char *fmt, va_list ap) {
    va_list copy;
    va_copy(copy, ap);
    snes_runtime_vlogf(fmt, copy);
    va_end(copy);
    return 0;
}

int printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    snes_runtime_vlogf(fmt, ap);
    va_end(ap);
    return 0;
}
