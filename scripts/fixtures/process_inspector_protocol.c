#define _GNU_SOURCE

#include <errno.h>
#include <linux/capability.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>

static int write_all(const void *buffer, size_t length) {
    const unsigned char *bytes = buffer;
    while (length > 0) {
        ssize_t written = write(STDOUT_FILENO, bytes, length);
        if (written < 0 && errno == EINTR) {
            continue;
        }
        if (written <= 0) {
            return -1;
        }
        bytes += written;
        length -= (size_t)written;
    }
    return 0;
}

int main(int argc, char **argv) {
    struct __user_cap_header_struct header = {
        .version = _LINUX_CAPABILITY_VERSION_3,
        .pid = 0,
    };
    struct __user_cap_data_struct capabilities[2] = {{0}};
    struct rlimit core_limit = {0, 0};
    static const unsigned char magic[16] = {
        'S', 'Y', 'N', 'T', 'A', 'U', 'R', '-', 'P', 'I', '-', 'V', '1', 0, 0, 0,
    };
    static const unsigned char path[] = "/bin/sh";
    const uint32_t length = (uint32_t)(sizeof(path) - 1);
    const unsigned char encoded_length[4] = {
        (unsigned char)(length >> 24),
        (unsigned char)(length >> 16),
        (unsigned char)(length >> 8),
        (unsigned char)length,
    };

    if (argc != 2 || argv[1][0] == '\0') {
        return 1;
    }
    for (const char *cursor = argv[1]; *cursor != '\0'; ++cursor) {
        if (*cursor < '0' || *cursor > '9') {
            return 1;
        }
    }
    if (syscall(SYS_capget, &header, capabilities) != 0
        || capabilities[0].effective != (1U << CAP_SYS_PTRACE)
        || capabilities[0].permitted != (1U << CAP_SYS_PTRACE)
        || capabilities[0].inheritable != 0
        || capabilities[1].effective != 0
        || capabilities[1].permitted != 0
        || capabilities[1].inheritable != 0) {
        return 1;
    }
    if (setrlimit(RLIMIT_CORE, &core_limit) != 0
        || prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) != 0
        || prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0
        || prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0) {
        return 1;
    }
    memset(capabilities, 0, sizeof(capabilities));
    if (syscall(SYS_capset, &header, capabilities) != 0
        || syscall(SYS_capget, &header, capabilities) != 0
        || capabilities[0].effective != 0
        || capabilities[0].permitted != 0
        || capabilities[0].inheritable != 0
        || capabilities[1].effective != 0
        || capabilities[1].permitted != 0
        || capabilities[1].inheritable != 0) {
        _exit(1);
    }
    return write_all(magic, sizeof(magic)) == 0
               && write_all(encoded_length, sizeof(encoded_length)) == 0
               && write_all(path, sizeof(path) - 1) == 0
           ? 0
           : 1;
}
