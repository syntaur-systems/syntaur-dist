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

#ifndef FIXTURE_AUTHORITY_GENERATIONS
#define FIXTURE_AUTHORITY_GENERATIONS 1
#endif

#if FIXTURE_AUTHORITY_GENERATIONS < 1 || FIXTURE_AUTHORITY_GENERATIONS > 9
#error "FIXTURE_AUTHORITY_GENERATIONS must be between 1 and 9"
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

static int files_are_equal(const char *left_path, const char *right_path) {
    FILE *left = fopen(left_path, "rb");
    FILE *right = fopen(right_path, "rb");
    unsigned char left_buffer[4096];
    unsigned char right_buffer[4096];
    int equal = 1;
    if (left == NULL || right == NULL) {
        if (left != NULL) {
            fclose(left);
        }
        if (right != NULL) {
            fclose(right);
        }
        return 0;
    }
    for (;;) {
        size_t left_size = fread(left_buffer, 1, sizeof(left_buffer), left);
        size_t right_size = fread(right_buffer, 1, sizeof(right_buffer), right);
        if (left_size != right_size ||
            memcmp(left_buffer, right_buffer, left_size) != 0) {
            equal = 0;
            break;
        }
        if (left_size < sizeof(left_buffer)) {
            if (ferror(left) || ferror(right)) {
                equal = 0;
            }
            break;
        }
    }
    if (fclose(left) != 0 || fclose(right) != 0) {
        equal = 0;
    }
    return equal;
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

static int has_exact_generation_names(const char *path) {
    DIR *directory = opendir(path);
    struct dirent *entry;
    int seen[FIXTURE_AUTHORITY_GENERATIONS] = {0};
    size_t count = 0;
    if (directory == NULL) {
        return 0;
    }
    while ((entry = readdir(directory)) != NULL) {
        size_t generation;
        int matched = 0;
        if (strcmp(entry->d_name, ".") == 0 ||
            strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        for (generation = 1; generation <= FIXTURE_AUTHORITY_GENERATIONS;
             ++generation) {
            char expected[32];
            int written =
                snprintf(expected, sizeof(expected), "generation-%zu", generation);
            if (written < 0 || (size_t)written >= sizeof(expected)) {
                closedir(directory);
                return 0;
            }
            if (strcmp(entry->d_name, expected) == 0) {
                seen[generation - 1] = 1;
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
    if (closedir(directory) != 0 ||
        count != FIXTURE_AUTHORITY_GENERATIONS) {
        return 0;
    }
    for (size_t index = 0; index < FIXTURE_AUTHORITY_GENERATIONS; ++index) {
        if (!seen[index]) {
            return 0;
        }
    }
    return 1;
}

static int generation_layout_is_exact(size_t generation) {
    static const char *const generation_names[] = {
        "release-authority-v2.json",
        "release-authority-v2.json.cosign.bundle",
        "syntaur-build-authority-provision",
        "syntaur-ship-linux-x86_64",
        "syntaur-verify-linux-x86_64",
        "trusted-workflow-commit",
    };
    static const char *const generation_data[] = {
        "release-authority-v2.json",
        "release-authority-v2.json.cosign.bundle",
        "trusted-workflow-commit",
    };
    static const char *const generation_executables[] = {
        "syntaur-build-authority-provision",
        "syntaur-ship-linux-x86_64",
        "syntaur-verify-linux-x86_64",
    };
    char directory[256];
    int written = snprintf(
        directory, sizeof(directory),
        "/etc/syntaur/release-authority/release-authority/generation-%zu",
        generation);
    if (written < 0 || (size_t)written >= sizeof(directory) ||
        !has_exact_metadata(directory, 0555, 1) ||
        !has_exact_names(
            directory, generation_names,
            sizeof(generation_names) / sizeof(generation_names[0]))) {
        return 0;
    }
    for (size_t index = 0;
         index < sizeof(generation_data) / sizeof(generation_data[0]);
         ++index) {
        char path[384];
        written = snprintf(path, sizeof(path), "%s/%s", directory,
                           generation_data[index]);
        if (written < 0 || (size_t)written >= sizeof(path) ||
            !has_exact_metadata(path, 0444, 0)) {
            return 0;
        }
    }
    for (size_t index = 0;
         index < sizeof(generation_executables) /
                     sizeof(generation_executables[0]);
         ++index) {
        char path[384];
        written = snprintf(path, sizeof(path), "%s/%s", directory,
                           generation_executables[index]);
        if (written < 0 || (size_t)written >= sizeof(path) ||
            !has_exact_metadata(path, 0555, 0)) {
            return 0;
        }
    }
    return 1;
}

static int authority_layout_is_exact(void) {
    static const char *const root_names[] = {
        "genesis",
        "release-authority",
        "release-authority-v2.json",
        "release-authority-v2.json.cosign.bundle",
        "trusted-workflow-commit",
    };
    static const char *const genesis_names[] = {
        "genesis-install-receipt-v1.json",
        "genesis-validation.json",
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
    size_t index;
    const char *root = "/etc/syntaur/release-authority";
    const char *genesis = "/etc/syntaur/release-authority/genesis";
    const char *parent =
        "/etc/syntaur/release-authority/release-authority";
    static const char *const active_names[] = {
        "release-authority-v2.json",
        "release-authority-v2.json.cosign.bundle",
        "trusted-workflow-commit",
    };

    if (!has_exact_metadata(root, 0755, 1) ||
        !has_exact_metadata(genesis, 0555, 1) ||
        !has_exact_metadata(parent, 0755, 1) ||
        !has_exact_names(root, root_names,
                         sizeof(root_names) / sizeof(root_names[0])) ||
        !has_exact_names(genesis, genesis_names,
                         sizeof(genesis_names) / sizeof(genesis_names[0])) ||
        !has_exact_generation_names(parent)) {
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
    for (index = 1; index <= FIXTURE_AUTHORITY_GENERATIONS; ++index) {
        if (!generation_layout_is_exact(index)) {
            return 0;
        }
    }
    for (index = 0; index < sizeof(active_names) / sizeof(active_names[0]);
         ++index) {
        char active[256];
        char retained[384];
        int active_written = snprintf(
            active, sizeof(active), "%s/%s", root, active_names[index]);
        int retained_written = snprintf(
            retained, sizeof(retained), "%s/generation-%d/%s", parent,
            FIXTURE_AUTHORITY_GENERATIONS, active_names[index]);
        if (active_written < 0 || (size_t)active_written >= sizeof(active) ||
            retained_written < 0 ||
            (size_t)retained_written >= sizeof(retained) ||
            !files_are_equal(active, retained)) {
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
        if (access("/run/syntaur-fixture-authority-status-fail", F_OK) == 0) {
            fputs("fixture authority-status injected failure\n", stderr);
            return 79;
        }
        printf("fixture authority status (%s): exact\n", FIXTURE_ROLE_MARKER);
        return 0;
    }
    return 64;
}
