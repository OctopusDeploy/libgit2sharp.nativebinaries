<#
.SYNOPSIS
    Builds a version of libgit2 and copies it to the nuget packaging directory.
.PARAMETER test
    If set, run the libgit2 tests on the desired version.
.PARAMETER debug
    If set, build the "Debug" configuration of libgit2, rather than "Release" (default).
.PARAMETER x86
    If set, the x86 version will be built.
.PARAMETER x64
    If set, the x64 version will be built.
.PARAMETER arm64
    If set, the arm64 version will be built.
#>

Param(
    [switch]$test,
    [switch]$debug,
    [switch]$x86,
    [switch]$x64,
    [switch]$arm64
)

Set-StrictMode -Version Latest

$projectDirectory = Split-Path $MyInvocation.MyCommand.Path
$libgit2Directory = Join-Path $projectDirectory "libgit2"
$x86Directory = Join-Path $projectDirectory "nuget.package\runtimes\win-x86\native"
$x64Directory = Join-Path $projectDirectory "nuget.package\runtimes\win-x64\native"
$arm64Directory = Join-Path $projectDirectory "nuget.package\runtimes\win-arm64\native"
$hashFile = Join-Path $projectDirectory "nuget.package\libgit2\libgit2_hash.txt"
$sha = Get-Content $hashFile
$binaryFilename = "git2-" + $sha.Substring(0,7)

$build_tests = 'OFF'
if ($test.IsPresent) { $build_tests = 'ON' }

$configuration = "Release"
if ($debug.IsPresent) { $configuration = "Debug" }

function Run-Command([scriptblock]$Command, [switch]$Fatal, [switch]$Quiet) {
    $output = ""
    if ($Quiet) {
        $output = & $Command 2>&1
    } else {
        & $Command
    }

    if (!$Fatal) {
        return
    }

    $exitCode = 0
    if ($LastExitCode -ne 0) {
        $exitCode = $LastExitCode
    } elseif (!$?) {
        $exitCode = 1
    } else {
        return
    }

    $error = "``$Command`` failed"
    if ($output) {
        Write-Host -ForegroundColor yellow $output
        $error += ". See output above."
    }
    Throw $error
}

function Find-CMake {
    # Look for cmake.exe in $Env:PATH.
    $cmake = @(Get-Command cmake.exe)[0] 2>$null
    if ($cmake) {
        $cmake = $cmake.Definition
    } else {
        # Look for the highest-versioned cmake.exe in its default location.
        $cmake = @(Resolve-Path (Join-Path ${Env:ProgramFiles(x86)} "CMake *\bin\cmake.exe"))
        if ($cmake) {
            $cmake = $cmake[-1].Path
        }
    }
    if (!$cmake) {
        throw "Error: Can't find cmake.exe"
    }
    $cmake
}

function Ensure-Property($expected, $propertyValue, $propertyName, $path) {
    if ($propertyValue -eq $expected) {
        return
    }

    throw "Error: Invalid '$propertyName' property in generated '$path' (Expected: $expected - Actual: $propertyValue)"
}

function Assert-Consistent-Naming($expected, $path) {
    $dll = get-item $path

    Ensure-Property $expected $dll.Name "Name" $dll.Fullname
    Ensure-Property $expected $dll.VersionInfo.InternalName "VersionInfo.InternalName" $dll.Fullname
    Ensure-Property $expected $dll.VersionInfo.OriginalFilename "VersionInfo.OriginalFilename" $dll.Fullname
}

function Install-Libssh2($arch) {
    $triplet = "$arch-windows"

    $vcpkg = Join-Path $Env:VCPKG_INSTALLATION_ROOT "vcpkg.exe"
    if (-not (Test-Path $vcpkg)) {
        throw "Error: vcpkg not found at $Env:VCPKG_INSTALLATION_ROOT"
    }

    Write-Host "Installing libssh2 for $triplet via vcpkg..."
    Run-Command -Fatal -Quiet { & $vcpkg install "libssh2:$triplet" }

    $installedDir = Join-Path $Env:VCPKG_INSTALLATION_ROOT "installed\$triplet"

    return @{
        IncludeDir = Join-Path $installedDir "include"
        LibDir     = Join-Path $installedDir "lib"
        BinDir     = Join-Path $installedDir "bin"
        Prefix     = $installedDir
    }
}

try {
    if ((!$x86.isPresent -and !$x64.IsPresent) -and !$arm64.IsPresent) {
        Write-Output -Stderr "Error: usage $MyInvocation.MyCommand [-x86] [-x64] [-arm64]"
	Exit
    }

    Push-Location $libgit2Directory

    $cmake = Find-CMake
    $ctest = Join-Path (Split-Path -Parent $cmake) "ctest.exe"

    Run-Command -Quiet { & remove-item build -recurse -force -ErrorAction Ignore }
    Run-Command -Quiet { & mkdir build }
    cd build

    if ($x86.IsPresent) {
        Write-Output "Building x86..."
        $ssh2 = Install-Libssh2 "x86"
        Run-Command -Fatal { & $cmake -A Win32 -D USE_SSH=ON -D USE_HTTPS=Schannel -D "BUILD_TESTS=$build_tests" -D "BUILD_CLI=OFF" -D "LIBGIT2_FILENAME=$binaryFilename" -D "CMAKE_PREFIX_PATH=$($ssh2.Prefix)" .. }
        Run-Command -Fatal { & $cmake --build . --config $configuration }
        if ($test.IsPresent) { Run-Command -Quiet -Fatal { & $ctest -V . } }
        cd $configuration
        Assert-Consistent-Naming "$binaryFilename.dll" "*.dll"
        Run-Command -Quiet { & rm *.exp }
        Run-Command -Quiet { & rm $x86Directory\* -ErrorAction Ignore }
        Run-Command -Quiet { & mkdir -fo $x86Directory }
        Run-Command -Quiet -Fatal { & copy -fo * $x86Directory -Exclude *.lib }
        Run-Command -Quiet -Fatal { & copy -fo (Join-Path $ssh2.BinDir "libssh2.dll") $x86Directory }
        if (-not (Test-Path (Join-Path $x86Directory "libssh2.dll"))) { throw "Error: libssh2.dll was not copied to $x86Directory" }
        cd ..
    }

    if ($x64.IsPresent) {
        Write-Output "Building x64..."
        $ssh2 = Install-Libssh2 "x64"
        Run-Command -Quiet { & mkdir build64 }
        cd build64
        Run-Command -Fatal { & $cmake -A x64 -D USE_SSH=ON -D USE_HTTPS=Schannel -D "BUILD_TESTS=$build_tests" -D "BUILD_CLI=OFF" -D "LIBGIT2_FILENAME=$binaryFilename" -D "CMAKE_PREFIX_PATH=$($ssh2.Prefix)" ../.. }
        Run-Command -Fatal { & $cmake --build . --config $configuration }
        if ($test.IsPresent) { Run-Command -Quiet -Fatal { & $ctest -V . } }
        cd $configuration
        Assert-Consistent-Naming "$binaryFilename.dll" "*.dll"
        Run-Command -Quiet { & rm *.exp }
        Run-Command -Quiet { & rm $x64Directory\* -ErrorAction Ignore }
        Run-Command -Quiet { & mkdir -fo $x64Directory }
        Run-Command -Quiet -Fatal { & copy -fo * $x64Directory -Exclude *.lib }
        Run-Command -Quiet -Fatal { & copy -fo (Join-Path $ssh2.BinDir "libssh2.dll") $x64Directory }
        if (-not (Test-Path (Join-Path $x64Directory "libssh2.dll"))) { throw "Error: libssh2.dll was not copied to $x64Directory" }
    }

    if ($arm64.IsPresent) {
        Write-Output "Building arm64..."
        $ssh2 = Install-Libssh2 "arm64"
        Run-Command -Quiet { & mkdir buildarm64 }
        cd buildarm64
        Run-Command -Fatal { & $cmake -A ARM64 -D USE_SSH=ON -D USE_HTTPS=Schannel -D "BUILD_TESTS=$build_tests" -D "BUILD_CLI=OFF" -D "LIBGIT2_FILENAME=$binaryFilename" -D "CMAKE_PREFIX_PATH=$($ssh2.Prefix)" ../.. }
        Run-Command -Fatal { & $cmake --build . --config $configuration }
        if ($test.IsPresent) { Run-Command -Quiet -Fatal { & $ctest -V . } }
        cd $configuration
        Assert-Consistent-Naming "$binaryFilename.dll" "*.dll"
        Run-Command -Quiet { & rm *.exp }
        Run-Command -Quiet { & rm $arm64Directory\* -ErrorAction Ignore  }
        Run-Command -Quiet { & mkdir -fo $arm64Directory }
        Run-Command -Quiet -Fatal { & copy -fo * $arm64Directory -Exclude *.lib }
        Run-Command -Quiet -Fatal { & copy -fo (Join-Path $ssh2.BinDir "libssh2.dll") $arm64Directory }
        if (-not (Test-Path (Join-Path $arm64Directory "libssh2.dll"))) { throw "Error: libssh2.dll was not copied to $arm64Directory" }
    }

    Write-Output "Done!"
}
finally {
    Pop-Location
}
