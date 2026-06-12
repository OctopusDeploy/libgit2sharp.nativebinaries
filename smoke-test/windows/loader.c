/* LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR makes the loader resolve git2's sibling DLLs
 * from git2's own directory (where libssh2.dll/z.dll live in the broken build),
 * so a missing transitive dep (VCRUNTIME140.dll) surfaces as ERROR_MOD_NOT_FOUND.
 */
#include <windows.h>
#include <stdio.h>

typedef int (*git_libgit2_init_fn)(void);

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: loader <full-path-to-git2.dll>\n");
        return 2;
    }

    const char *dllPath = argv[1];

    HMODULE library = LoadLibraryExA(dllPath, NULL, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR);
    if (!library) {
        DWORD error = GetLastError();
        fprintf(stderr, "LoadLibraryEx('%s') failed: error %lu (0x%08lX)\n", dllPath, error, error);
        return 1;
    }

    git_libgit2_init_fn git_libgit2_init = (git_libgit2_init_fn)GetProcAddress(library, "git_libgit2_init");
    if (!git_libgit2_init) {
        fprintf(stderr, "GetProcAddress(git_libgit2_init) failed: %lu\n", GetLastError());
        return 1;
    }

    int initCount = git_libgit2_init();
    printf("git_libgit2_init() returned %d\n", initCount);

    /* git_libgit2_init returns the initialization count (>=1) on success. */
    return initCount > 0 ? 0 : 1;
}
