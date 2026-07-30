#define _POSIX_C_SOURCE 200809L

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef FIXTURE_ROLE_MARKER
#define FIXTURE_ROLE_MARKER "unspecified"
#endif

static int has_exact_metadata(const char *path, mode_t mode, int directory) {
    struct stat metadata;
    if (lstat(path, &metadata) != 0 || metadata.st_uid != 0 ||
        metadata.st_gid != 0 || (metadata.st_mode & 07777) != mode) {
        return 0;
    }
    if (directory) {
        return S_ISDIR(metadata.st_mode);
    }
    return S_ISREG(metadata.st_mode) && metadata.st_nlink == 1;
}

static int has_exact_names(const char *path, const char *const *expected,
                           size_t expected_count) {
    DIR *directory = opendir(path);
    struct dirent *entry;
    size_t count = 0;
    if (directory == NULL) {
        return 0;
    }
    while ((entry = readdir(directory)) != NULL) {
        size_t index;
        int matched = 0;
        if (strcmp(entry->d_name, ".") == 0 ||
            strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        for (index = 0; index < expected_count; ++index) {
            if (strcmp(entry->d_name, expected[index]) == 0) {
                matched = 1;
                break;
            }
        }
        if (!matched) {
            closedir(directory);
            return 0;
        }
        ++count;
    }
    if (closedir(directory) != 0) {
        return 0;
    }
    return count == expected_count;
}

static int authority_layout_is_exact(void) {
    static const char *const root_names[] = {
        "genesis",
        "release-authority",
        "release-authority-v2.json",
        "release-authority-v2.json.cosign.bundle",
        "trusted-workflow-commit",
    };
    static const char *const parent_names[] = {"generation-1"};
    static const char *const genesis_names[] = {
        "genesis-install-receipt-v1.json",
        "genesis-validation.json",
    };
    static const char *const generation_names[] = {
        "release-authority-v2.json",
        "release-authority-v2.json.cosign.bundle",
        "syntaur-build-authority-provision",
        "syntaur-ship-linux-x86_64",
        "syntaur-verify-linux-x86_64",
        "trusted-workflow-commit",
    };
    static const char *const genesis_data[] = {
        "/etc/syntaur/release-authority/genesis/"
        "genesis-install-receipt-v1.json",
        "/etc/syntaur/release-authority/genesis/genesis-validation.json",
    };
    static const char *const root_data[] = {
        "/etc/syntaur/release-authority/release-authority-v2.json",
        "/etc/syntaur/release-authority/release-authority-v2.json.cosign.bundle",
        "/etc/syntaur/release-authority/trusted-workflow-commit",
    };
    static const char *const generation_data[] = {
        "/etc/syntaur/release-authority/release-authority/generation-1/"
        "release-authority-v2.json",
        "/etc/syntaur/release-authority/release-authority/generation-1/"
        "release-authority-v2.json.cosign.bundle",
        "/etc/syntaur/release-authority/release-authority/generation-1/"
        "trusted-workflow-commit",
    };
    static const char *const generation_executables[] = {
        "/etc/syntaur/release-authority/release-authority/generation-1/"
        "syntaur-build-authority-provision",
        "/etc/syntaur/release-authority/release-authority/generation-1/"
        "syntaur-ship-linux-x86_64",
        "/etc/syntaur/release-authority/release-authority/generation-1/"
        "syntaur-verify-linux-x86_64",
    };
    size_t index;
    const char *root = "/etc/syntaur/release-authority";
    const char *genesis = "/etc/syntaur/release-authority/genesis";
    const char *parent =
        "/etc/syntaur/release-authority/release-authority";
    const char *generation =
        "/etc/syntaur/release-authority/release-authority/generation-1";

    if (!has_exact_metadata(root, 0755, 1) ||
        !has_exact_metadata(genesis, 0555, 1) ||
        !has_exact_metadata(parent, 0755, 1) ||
        !has_exact_metadata(generation, 0555, 1) ||
        !has_exact_names(root, root_names,
                         sizeof(root_names) / sizeof(root_names[0])) ||
        !has_exact_names(genesis, genesis_names,
                         sizeof(genesis_names) / sizeof(genesis_names[0])) ||
        !has_exact_names(parent, parent_names,
                         sizeof(parent_names) / sizeof(parent_names[0])) ||
        !has_exact_names(generation, generation_names,
                         sizeof(generation_names) /
                             sizeof(generation_names[0]))) {
        return 0;
    }
    for (index = 0;
         index < sizeof(genesis_data) / sizeof(genesis_data[0]);
         ++index) {
        if (!has_exact_metadata(genesis_data[index], 0444, 0)) {
            return 0;
        }
    }
    for (index = 0; index < sizeof(root_data) / sizeof(root_data[0]); ++index) {
        if (!has_exact_metadata(root_data[index], 0444, 0)) {
            return 0;
        }
    }
    for (index = 0;
         index < sizeof(generation_data) / sizeof(generation_data[0]);
         ++index) {
        if (!has_exact_metadata(generation_data[index], 0444, 0)) {
            return 0;
        }
    }
    for (index = 0;
         index < sizeof(generation_executables) /
                     sizeof(generation_executables[0]);
         ++index) {
        if (!has_exact_metadata(generation_executables[index], 0555, 0)) {
            return 0;
        }
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "authority-status") == 0) {
        const char *single_uid_fixture =
            getenv("SYNTAUR_BOOTSTRAP_SINGLE_UID_FIXTURE");
        if (geteuid() == 0 &&
            (single_uid_fixture == NULL ||
             strcmp(single_uid_fixture, "1") != 0)) {
            fputs("fixture authority-status rejects privileged execution\n", stderr);
            return 77;
        }
        if (!authority_layout_is_exact()) {
            fputs("fixture authority-status found an inexact layout\n", stderr);
            return 78;
        }
        printf("fixture authority status (%s): exact\n", FIXTURE_ROLE_MARKER);
        return 0;
    }
    return 64;
}
