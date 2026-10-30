// fcitx5-im-watch: tiny watcher for the Vinikey bar widget.
//
// fcitx5 emits no D-Bus signal when the input method changes (Ctrl+Space is handled
// inside fcitx5), so this asks org.fcitx.Fcitx.Controller1.CurrentInputMethod every
// interval over ONE persistent session-bus connection and reports only changes.
// It speaks the D-Bus wire protocol directly (libc only, no libdbus/libsystemd).
//
// Safety: every call carries the NO_AUTO_START flag, so it can never D-Bus-activate a
// stray fcitx5 while the omarchy-fcitx5 service is down. It only reads.
//
// Usage: fcitx5-im-watch [interval_ms] [statefile]
//   no statefile  print the method name on stdout on every change.
//   statefile     shared mode for several bars: take flock(statefile.lock) (extra
//                 instances block there at ~0 CPU and take over when the holder dies),
//                 then rewrite statefile in place as one 32-byte record on every change
//                 and print "active" once on stdout after the first write.
// The value is the input method name ("bamboo", "keyboard-us", ...) or "-" when fcitx5
// is not on the bus or no input context has focus. The process dies with its parent.
//
// Build: cc -O2 -s [-static] -o ~/.local/bin/fcitx5-im-watch fcitx5-im-watch.c
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define TIMEOUT_MS 1000

static uint8_t msg[1024];     // outgoing message
static size_t len;
static uint32_t serial;

static void pad(size_t a) { while (len % a) msg[len++] = 0; }
static void put_u32(uint32_t v) { pad(4); memcpy(msg + len, &v, 4); len += 4; }
static void put_str(const char *s) {
    uint32_t n = strlen(s); put_u32(n); memcpy(msg + len, s, n + 1); len += n + 1;
}
static void put_field(uint8_t code, char sig, const char *v) {
    pad(8); msg[len++] = code; msg[len++] = 1; msg[len++] = sig; msg[len++] = 0; put_str(v);
}

// Build a method call without arguments (little-endian); returns its serial.
static uint32_t build_call(const char *dest, const char *path, const char *iface, const char *member) {
    msg[0] = 'l'; msg[1] = 1 /* METHOD_CALL */; msg[2] = 0x2 /* NO_AUTO_START */; msg[3] = 1;
    len = 4;
    put_u32(0); put_u32(++serial); put_u32(0);        // body length, serial, fields length
    size_t start = len;
    put_field(1, 'o', path); put_field(6, 's', dest); put_field(2, 's', iface); put_field(3, 's', member);
    uint32_t flen = len - start; memcpy(msg + 12, &flen, 4);
    pad(8);
    return serial;
}

static int send_all(int fd, const void *p, size_t n) {
    while (n) {
        ssize_t w = send(fd, p, n, MSG_NOSIGNAL);
        if (w <= 0) return -1;
        p = (const char *)p + w; n -= w;
    }
    return 0;
}

static int recv_all(int fd, void *p, size_t n) {
    while (n) {
        struct pollfd pf = { fd, POLLIN, 0 };
        if (poll(&pf, 1, TIMEOUT_MS) <= 0) return -1;
        ssize_t r = recv(fd, p, n, 0);
        if (r <= 0) return -1;
        p = (char *)p + r; n -= r;
    }
    return 0;
}

// Read messages until the reply to `want` arrives, skipping anything else (signals).
// Returns 2 (method return) or 3 (error), -1 on I/O or protocol failure. A string
// reply body is copied to out.
static int read_reply(int fd, uint32_t want, char *out, size_t outsz) {
    static uint8_t m[65536];
    for (;;) {
        if (recv_all(fd, m, 16) || m[0] != 'l') return -1;
        uint32_t blen, flen;
        memcpy(&blen, m + 4, 4); memcpy(&flen, m + 12, 4);
        size_t hdr = (16 + (size_t)flen + 7) & ~(size_t)7, total = hdr + blen;
        if (total > sizeof m || recv_all(fd, m + 16, total - 16)) return -1;
        uint32_t reply_serial = 0;
        for (size_t i = 16; i + 4 <= 16 + flen; ) {      // header fields: (code, variant)
            i = (i + 7) & ~(size_t)7;
            if (i + 4 > 16 + flen) break;
            uint8_t code = m[i], siglen = m[i + 1]; char sig = m[i + 2];
            size_t j = i + 3 + siglen;
            if (sig == 'u') {
                j = (j + 3) & ~(size_t)3;
                if (code == 5) memcpy(&reply_serial, m + j, 4);
                j += 4;
            } else if (sig == 's' || sig == 'o') {
                uint32_t n; j = (j + 3) & ~(size_t)3; memcpy(&n, m + j, 4); j += 4 + (size_t)n + 1;
            } else if (sig == 'g') {
                j += 1 + (size_t)m[j] + 1;
            } else return -1;
            i = j;
        }
        if ((m[1] == 2 || m[1] == 3) && reply_serial == want) {
            if (m[1] == 2 && out && blen >= 5) {
                uint32_t n; memcpy(&n, m + hdr, 4);
                if (n < outsz && 4 + (size_t)n < blen) { memcpy(out, m + hdr + 4, n); out[n] = 0; }
            }
            return m[1];
        }
    }
}

// Connect to the session bus (unix:path=... or $XDG_RUNTIME_DIR/bus), authenticate, Hello.
static int bus_connect(void) {
    struct sockaddr_un sa = { .sun_family = AF_UNIX };
    const char *addr = getenv("DBUS_SESSION_BUS_ADDRESS"), *p;
    if (addr && (p = strstr(addr, "unix:path="))) {
        p += 10;
        size_t n = strcspn(p, ",;");
        if (n >= sizeof sa.sun_path) return -1;
        memcpy(sa.sun_path, p, n);
    } else {
        const char *rt = getenv("XDG_RUNTIME_DIR");
        if (!rt) return -1;
        snprintf(sa.sun_path, sizeof sa.sun_path, "%s/bus", rt);
    }
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;
    char uid[16], hex[40] = "", line[128];
    snprintf(uid, sizeof uid, "%u", (unsigned)getuid());
    for (char *c = uid; *c; c++) sprintf(hex + strlen(hex), "%02x", (unsigned char)*c);
    int n = snprintf(line, sizeof line, "%cAUTH EXTERNAL %s\r\n", 0, hex);
    size_t got = 0;
    if (connect(fd, (struct sockaddr *)&sa, sizeof sa) < 0 || send_all(fd, line, (size_t)n)) goto fail;
    while (got < sizeof line - 1) {
        if (recv_all(fd, line + got, 1)) goto fail;
        if (line[got++] == '\n') break;
    }
    if (strncmp(line, "OK ", 3) || send_all(fd, "BEGIN\r\n", 7)) goto fail;
    serial = 0;
    uint32_t s = build_call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello");
    if (send_all(fd, msg, len) || read_reply(fd, s, NULL, 0) != 2) goto fail;
    return fd;
fail:
    close(fd);
    return -1;
}

int main(int argc, char **argv) {
    // Die with the shell that spawned us, so a shell restart leaves no orphans.
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (getppid() == 1) return 0;

    long ms = argc > 1 ? atol(argv[1]) : 100;
    if (ms < 20) ms = 20;
    struct timespec interval = { ms / 1000, (ms % 1000) * 1000000L };

    int state = -1;
    if (argc > 2) {
        char lock[512];
        snprintf(lock, sizeof lock, "%s.lock", argv[2]);
        int lfd = open(lock, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
        if (lfd < 0 || flock(lfd, LOCK_EX) < 0) return 1;   // standby: blocks here
        state = open(argv[2], O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
        if (state < 0) return 1;
    }

    int fd = -1, announced = 0;
    char cur[128], last[128] = "";
    for (;;) {
        strcpy(cur, "-");
        if (fd < 0) fd = bus_connect();
        if (fd >= 0) {
            uint32_t s = build_call("org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1",
                                    "CurrentInputMethod");
            int r = send_all(fd, msg, len) ? -1 : read_reply(fd, s, cur, sizeof cur);
            if (r < 0) { close(fd); fd = -1; strcpy(cur, "-"); }   // reconnect next round
            else if (r != 2 || !cur[0]) strcpy(cur, "-");          // not on the bus / no focus
        }
        if (strcmp(cur, last)) {
            if (state >= 0) {
                char rec[32];
                size_t n = strlen(cur) < 30 ? strlen(cur) : 30;
                memset(rec, ' ', sizeof rec); rec[31] = '\n'; memcpy(rec, cur, n);
                if (pwrite(state, rec, sizeof rec, 0) != (ssize_t)sizeof rec) return 1;  // one write
                if (!announced) {
                    announced = 1;
                    if (printf("active\n") < 0 || fflush(stdout) == EOF) return 0;
                }
            } else if (printf("%s\n", cur) < 0 || fflush(stdout) == EOF) {
                return 0;
            }
            strcpy(last, cur);
        }
        nanosleep(&interval, NULL);
    }
}
