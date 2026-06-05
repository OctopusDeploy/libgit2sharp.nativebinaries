/* Minimal dlopen loader for the Linux libgit2 native binary smoke test. */
#include <dlfcn.h>
#include <stdio.h>

typedef int (*git_libgit2_init_fn)(void);

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: loader <path-to-libgit2.so>\n");
        return 2;
    }

    const char *libraryPath = argv[1];

    void *library = dlopen(libraryPath, RTLD_NOW | RTLD_GLOBAL);
    if (!library) {
        fprintf(stderr, "dlopen('%s') failed: %s\n", libraryPath, dlerror());
        return 1;
    }

    git_libgit2_init_fn git_libgit2_init = (git_libgit2_init_fn)dlsym(library, "git_libgit2_init");
    if (!git_libgit2_init) {
        fprintf(stderr, "dlsym(git_libgit2_init) failed: %s\n", dlerror());
        return 1;
    }

    int initCount = git_libgit2_init();
    printf("git_libgit2_init() returned %d\n", initCount);

    return initCount > 0 ? 0 : 1;
}
