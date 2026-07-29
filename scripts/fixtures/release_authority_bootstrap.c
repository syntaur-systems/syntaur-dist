#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "authority-status") == 0) {
        puts("fixture authority status: exact");
        return 0;
    }
    return 0;
}
