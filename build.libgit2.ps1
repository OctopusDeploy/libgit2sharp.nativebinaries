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

function Install-Libssh2($triplet) {
    $vcpkg = Join-Path $Env:VCPKG_INSTALLATION_ROOT "vcpkg.exe"
    if (-not (Test-Path $vcpkg)) {
        throw "Error: vcpkg not found at $Env:VCPKG_INSTALLATION_ROOT"
    }
    Write-Host "Installing libssh2 for $triplet via vcpkg..."
    & $vcpkg install "libssh2:$triplet"
    if ($LastExitCode -ne 0) { throw "vcpkg install failed" }

    $installedDir = Join-Path $Env:VCPKG_INSTALLATION_ROOT "installed\$triplet"
    $libssh2Dll = Join-Path $installedDir "bin\libssh2.dll"
    $libssh2Lib = Join-Path $installedDir "lib\libssh2.lib"
    $libssh2Include = Join-Path $installedDir "include"

    if (-not (Test-Path $libssh2Dll)) {
        throw "Error: libssh2.dll not found at $libssh2Dll"
    }

    return @{
        Dll = $libssh2Dll
        Library = $libssh2Lib
        IncludeDir = $libssh2Include
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
        $ssh2 = Install-Libssh2 "x86-windows"
        $vcpkgToolchain = Join-Path $Env:VCPKG_INSTALLATION_ROOT "scripts\buildsystems\vcpkg.cmake"
        Write-Output "Building x86..."
        Run-Command -Fatal { & $cmake -A Win32 -D USE_SSH=ON -D USE_HTTPS=Schannel -D "BUILD_TESTS=$build_tests" -D "BUILD_CLI=OFF" -D "LIBGIT2_FILENAME=$binaryFilename" -D "CMAKE_TOOLCHAIN_FILE=$vcpkgToolchain" -D "VCPKG_TARGET_TRIPLET=x86-windows" .. }
        Run-Command -Fatal { & $cmake --build . --config $configuration }
        if ($test.IsPresent) { Run-Command -Quiet -Fatal { & $ctest -V . } }
        cd $configuration
        Assert-Consistent-Naming "$binaryFilename.dll" "*.dll"
        Run-Command -Quiet { & rm *.exp }
        Run-Command -Quiet { & rm $x86Directory\* -ErrorAction Ignore }
        Run-Command -Quiet { & mkdir -fo $x86Directory }
        Run-Command -Quiet -Fatal { & copy -fo * $x86Directory -Exclude *.lib }
        Run-Command -Quiet -Fatal { & copy -fo $($ssh2.Dll) $x86Directory }
        Write-Output "Bundled libssh2.dll alongside libgit2"
        cd ..
    }

    if ($x64.IsPresent) {
        $ssh2 = Install-Libssh2 "x64-windows"
        $vcpkgToolchain = Join-Path $Env:VCPKG_INSTALLATION_ROOT "scripts\buildsystems\vcpkg.cmake"
        Write-Output "Building x64..."
        Run-Command -Quiet { & mkdir build64 }
        cd build64
        Run-Command -Fatal { & $cmake -A x64 -D USE_SSH=ON -D USE_HTTPS=Schannel -D "BUILD_TESTS=$build_tests" -D "BUILD_CLI=OFF" -D "LIBGIT2_FILENAME=$binaryFilename" -D "CMAKE_TOOLCHAIN_FILE=$vcpkgToolchain" -D "VCPKG_TARGET_TRIPLET=x64-windows" ../.. }
        Run-Command -Fatal { & $cmake --build . --config $configuration }
        if ($test.IsPresent) { Run-Command -Quiet -Fatal { & $ctest -V . } }
        cd $configuration
        Assert-Consistent-Naming "$binaryFilename.dll" "*.dll"
        Run-Command -Quiet { & rm *.exp }
        Run-Command -Quiet { & rm $x64Directory\* -ErrorAction Ignore }
        Run-Command -Quiet { & mkdir -fo $x64Directory }
        Run-Command -Quiet -Fatal { & copy -fo * $x64Directory -Exclude *.lib }
        Run-Command -Quiet -Fatal { & copy -fo $($ssh2.Dll) $x64Directory }
        Write-Output "Bundled libssh2.dll alongside libgit2"
    }

    if ($arm64.IsPresent) {
        $ssh2 = Install-Libssh2 "arm64-windows"
        $vcpkgToolchain = Join-Path $Env:VCPKG_INSTALLATION_ROOT "scripts\buildsystems\vcpkg.cmake"
        Write-Output "Building arm64..."
        Run-Command -Quiet { & mkdir buildarm64 }
        cd buildarm64
        Run-Command -Fatal { & $cmake -A ARM64 -D USE_SSH=ON -D USE_HTTPS=Schannel -D "BUILD_TESTS=$build_tests" -D "BUILD_CLI=OFF" -D "LIBGIT2_FILENAME=$binaryFilename" -D "CMAKE_TOOLCHAIN_FILE=$vcpkgToolchain" -D "VCPKG_TARGET_TRIPLET=arm64-windows" ../.. }
        Run-Command -Fatal { & $cmake --build . --config $configuration }
        if ($test.IsPresent) { Run-Command -Quiet -Fatal { & $ctest -V . } }
        cd $configuration
        Assert-Consistent-Naming "$binaryFilename.dll" "*.dll"
        Run-Command -Quiet { & rm *.exp }
        Run-Command -Quiet { & rm $arm64Directory\* -ErrorAction Ignore  }
        Run-Command -Quiet { & mkdir -fo $arm64Directory }
        Run-Command -Quiet -Fatal { & copy -fo * $arm64Directory -Exclude *.lib }
        Run-Command -Quiet -Fatal { & copy -fo $($ssh2.Dll) $arm64Directory }
        Write-Output "Bundled libssh2.dll alongside libgit2"
    }

    Write-Output "Done!"
}
finally {
    Pop-Location
}
