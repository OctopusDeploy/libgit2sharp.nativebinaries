# LibGit2Sharp.NativeBinaries

**[Libgit2Sharp][lg2s]** is a managed wrapper around **[libgit2][lg2]**, and as
such requires compilation of libgit2 for your platform.

LibGit2Sharp makes this easy by distributing, and leveraging as a dependency,
the **[LibGit2Sharp.NativeBinaries][lg2s-nb]** NuGet package.

This package contains the compiled versions of the libgit2 native library for
the following platforms:

 - Windows (x86, x64, arm64)
 - macOS (x64, arm64)
 - Linux
   - glibc: (x64, arm, arm64, ppc64le)
   - musl: (x64, arm, arm64)

 [lg2s-nb]: https://www.nuget.org/packages/LibGit2Sharp.NativeBinaries
 [lg2]: https://libgit2.github.com/
 [lg2s]: http://libgit2sharp.com/

## Script overview

The following scripts are used to build libgit2 and update this repo.

### build.libgit2.ps1

This script builds Windows libgit2 binaries. It requires Visual Studio 2019 to run.

To build x86 binaries:

```
build.libgit2.ps1 -x86
```

To build x64 binaries:

```
build.libgit2.ps1 -x64
```

To build arm64 binaries:

```
build.libgit2.ps1 -arm64
```

Multiple architecture parameters can be specified to build multiple binaries with a single execution of the script.

See the script for additional parameters.

### build.libgit2.sh

This script builds Linux and macOS binaries. It can be invoked directly, but for Linux binaries, `dockerbuild.sh` should be used instead.

### dockerbuild.sh

This script will build one of the Dockerfiles in the repo. It chooses which one to run based on the value of the `RID` environment variable. Using docker to build the Linux binaries for the various RIDs ensures that a specific environment and distro is used.

### UpdateLibgit2ToSha.ps1

This script is used to update the libgit2 submodule and update the references within the project to the correct libgit2 revision. 

You can update to a specific commit:

```
UpdateLibgit2ToSha.ps1 1a2b3c4
```

Or you can specify references:

```
UpdateLibgit2ToSha.ps1 master
```

## Building the package locally

After running the appropriate build script(s) to create binaries, the NuGet package needs to be created.

First, to use the same version locally that will be generated via CI, install the [minver-cli](https://www.nuget.org/packages/minver-cli) dotnet tool:

```
dotnet tool install --global minver-cli
```

Once that is installed, running the `minver` command will output a version:

```
MinVer: Using { Commit: 2453a6d, Tag: '2.0.312', Version: 2.0.312, Height: 3 }.
MinVer: Calculated version 2.0.313-alpha.0.3.
2.0.313-alpha.0.3
```

To create the package, use the the following command:

```
nuget.exe Pack nuget.package/NativeBinaries.nuspec -Version <version> -NoPackageAnalysis
```

Where `<version>` is the version from the MinVer tool or manually chosen version.


## Releasing

Releases are triggered by pushing a git tag. The tag format is:

```
<upstream-version>-octopus.<n>
```

Where `<upstream-version>` is the version from the upstream libgit2sharp.nativebinaries repo (e.g., `2.0.312`) and `<n>` is an incrementing number starting at 1. The incrementing number resets to 1 when the upstream version changes.

For example, for upstream version `2.0.312`:

```
git tag 2.0.312-octopus.1
git push origin 2.0.312-octopus.1
```

This triggers CI, which builds all native binaries, packs the NuGet package with the tag as its version, and pushes it to the configured feed.


## Bundled third-party libraries

libgit2 is built with SSH support through libssh2. Where libssh2 and OpenSSL end up depends on the platform.

| Platform | libssh2 | OpenSSL |
|---|---|---|
| Windows | Built by vcpkg with the WinCNG backend and statically linked into libgit2 | Not used, crypto comes from Windows CNG |
| Linux (glibc, musl and the `openssl1.1` variant) | Built from source in `docker/linux`, `docker/musl` and `docker/openssl1.1` and statically linked into libgit2 | Not bundled, the system OpenSSL is loaded at runtime |
| macOS | Built from source by `build.libgit2.sh` and bundled as `libssh2.1.dylib` | Bundled as `libcrypto.3.dylib` from Homebrew `openssl@3` |

The package ships a license text for each library under `nuget.package/libgit2/`.

- `libgit2.license.txt` is copied from the `COPYING` file of the libgit2 submodule by `UpdateLibgit2ToSha.ps1`.
- `libssh2.license.txt` and `openssl.license.txt` are maintained by hand from the `COPYING` file of the libssh2 release and the `LICENSE.txt` of the OpenSSL release.

### Updating libssh2

The version and checksum are repeated across several files, so a bump touches all of these.

1. Set `LIBSSH2_VERSION` and `LIBSSH2_SHA256` in the workflow-level `env:` in `.github/workflows/ci.yml`.
2. Update the same two defaults in `build.libgit2.sh`, `dockerbuild.sh`, and the `ARG` lines of `docker/linux`, `docker/musl` and `docker/openssl1.1`.
3. Update the version default in `build.libgit2.ps1` and `verify-build.sh`, which have no checksum.
4. In `build.libgit2.ps1`, move `$libssh2VcpkgBaseline` to a vcpkg commit that carries the new libssh2 version and set `$libssh2VcpkgPortVersion` to that port's `port-version`. These three values must agree or the Windows build fails.
5. In `nuget.package/libgit2/libssh2.license.txt`, replace the text below the preamble with the `COPYING` file of the new release and update the version named in the preamble.

`LIBSSH2_SHA256` is the SHA256 of the GitHub release asset `libssh2-<version>.tar.gz`, which is the file every build downloads.


## Notes on Visual Studio

Visual Studio 2019 is required to build the Windows native binaries, however you
do not need to install a *paid* version of Visual Studio. libgit2
can be compiled using [Visual Studio Community](https://visualstudio.microsoft.com/vs/community/),
which is free for building open source applications.
