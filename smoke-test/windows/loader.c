/* LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR makes the loader resolve git2's sibling DLLs
 * from git2's own directory (where libssh2.dll/z.dll live in the broken build),
 * so a missing transitive dep (VCRUNTIME140.dll) surfaces as ERROR_MOD_NOT_FOUND.
 */
#include <windows.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: loader <full-path-to-git2.dll>\n");
        return 2;
    }

    HMODULE h = LoadLibraryExA(argv[1], NULL, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR);
    if (!h) {
        DWORD e = GetLastError();
        fprintf(stderr, "LoadLibraryEx('%s') failed: error %lu (0x%08lX)\n", argv[1], e, e);
        return 1;
    }

    FARPROC p = GetProcAddress(h, "git_libgit2_init");
    if (!p) {
        fprintf(stderr, "GetProcAddress(git_libgit2_init) failed: %lu\n", GetLastError());
        return 1;
    }

    int rc = ((int (*)(void))p)();
    printf("git_libgit2_init() returned %d\n", rc);
    /* git_libgit2_init returns the initialization count (>=1) on success. */
    return rc > 0 ? 0 : 1;
}
