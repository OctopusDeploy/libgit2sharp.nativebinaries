/* Minimal dlopen loader for the Linux libgit2 native binary smoke test. */
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: loader <path-to-libgit2.so>\n");
        return 2;
    }
    void *h = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
    if (!h) {
        fprintf(stderr, "dlopen('%s') failed: %s\n", argv[1], dlerror());
        return 1;
    }
    int (*init)(void) = (int (*)(void))dlsym(h, "git_libgit2_init");
    if (!init) {
        fprintf(stderr, "dlsym(git_libgit2_init) failed: %s\n", dlerror());
        return 1;
    }
    int rc = init();
    printf("git_libgit2_init() returned %d\n", rc);
    return rc > 0 ? 0 : 1;
}
