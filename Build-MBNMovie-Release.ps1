[CmdletBinding()]
param(
    [string] $AndroidSerial = '7bce7cbc',
    [switch] $SkipAndroidInstall,
    [string] $FlutterSdk = $env:MBN_FLUTTER_SDK
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The configured Runflare mirror has occasionally returned archives whose
# content hash does not match pub's lock data. Release builds use the canonical
# package host so a corrupt mirror cannot make the build intermittently fail.
$env:PUB_HOSTED_URL = 'https://pub.dev'

$projectRoot = Split-Path -Parent $PSCommandPath
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$releaseRoot = Join-Path $projectRoot 'releases'
$stagingRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ("MBNMovie-release-{0}" -f [guid]::NewGuid().ToString('N'))

function Invoke-Flutter {
    param([Parameter(Mandatory)][string[]] $Arguments)

    # Windows PowerShell can promote a native program's stderr records to
    # terminating PowerShell errors when ErrorActionPreference is Stop. Flutter
    # and Gradle legitimately use stderr for diagnostics, so let the native
    # process finish and decide success exclusively from its exit code.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        if ($Arguments.Count -gt 0 -and $Arguments[0] -eq 'build') {
            $Arguments += '--dart-define-from-file=.signing/api-config.json'
        }
        & $script:flutterCommand @Arguments
        $flutterExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($flutterExitCode -ne 0) {
        throw "Flutter command failed: flutter $($Arguments -join ' ')"
    }
}

function Find-SevenZip {
    $commands = @('7z.exe', '7zz.exe')
    foreach ($commandName in $commands) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    $knownPaths = @(
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe')
    )
    if (${env:ProgramFiles(x86)}) {
        $knownPaths += Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'
    }

    foreach ($candidate in $knownPaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Find-Adb {
    $command = Get-Command 'adb.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $knownPaths = @(
        'C:\Users\MBN\Desktop\platform-tools\adb.exe',
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
    )
    foreach ($candidate in $knownPaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Install-AndroidPackage {
    param([Parameter(Mandatory)][string] $ApkPath)

    if ($SkipAndroidInstall) {
        Write-Host 'Android install skipped by -SkipAndroidInstall.' `
            -ForegroundColor Yellow
        return
    }

    $adb = Find-Adb
    if ($null -eq $adb) {
        Write-Host 'Android install skipped: adb.exe was not found.' `
            -ForegroundColor Yellow
        return
    }

    $deviceLines = & $adb 'devices'
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Android install skipped: ADB could not list devices.' `
            -ForegroundColor Yellow
        return
    }

    $readyPattern = '^' + [regex]::Escape($AndroidSerial) + '\s+device(?:\s|$)'
    $phoneIsReady = $deviceLines | Where-Object { $_ -match $readyPattern }
    if (-not $phoneIsReady) {
        Write-Host `
            "Android install skipped: phone $AndroidSerial is not connected and authorized." `
            -ForegroundColor Yellow
        return
    }

    Write-Host "Installing APK on phone $AndroidSerial..." -ForegroundColor Cyan
    & $adb '-s' $AndroidSerial 'install' '-r' $ApkPath
    if ($LASTEXITCODE -ne 0) {
        throw "ADB failed to install the APK on phone $AndroidSerial."
    }
    Write-Host 'Android APK installed successfully.' -ForegroundColor Green
}

function Remove-StagingDirectory {
    if (-not (Test-Path -LiteralPath $stagingRoot)) {
        return
    }

    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $resolvedStage = [IO.Path]::GetFullPath($stagingRoot)
    $expectedPrefix = $tempRoot + [IO.Path]::DirectorySeparatorChar
    $stageName = Split-Path -Leaf $resolvedStage

    if (-not $resolvedStage.StartsWith(
        $expectedPrefix,
        [StringComparison]::OrdinalIgnoreCase
    ) -or -not $stageName.StartsWith('MBNMovie-release-')) {
        throw "Refusing to remove an unexpected staging path: $resolvedStage"
    }

    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}

if (-not (Test-Path -LiteralPath $pubspecPath -PathType Leaf)) {
    throw "pubspec.yaml was not found at $pubspecPath"
}

$versionMatch = Select-String `
    -LiteralPath $pubspecPath `
    -Pattern '^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$' |
    Select-Object -First 1
if ($null -eq $versionMatch) {
    throw 'Could not read the application version from pubspec.yaml.'
}

$version = $versionMatch.Matches[0].Groups[1].Value
$versionDirectory = Join-Path $releaseRoot $version
$androidOutput = Join-Path `
    $versionDirectory `
    "MBNMovie-Android-arm64-v8a-$version.apk"
$androidLegacyOutput = Join-Path `
    $versionDirectory `
    "MBNMovie-Android-armeabi-v7a-$version.apk"
$windowsArchive = Join-Path `
    $versionDirectory `
    "MBNMovie-Windows-x64-$version.zip"
if ($FlutterSdk) {
    $flutterCommand = Join-Path $FlutterSdk 'bin/flutter.bat'
} elseif (Test-Path -LiteralPath 'C:/dev/flutter-3.32.8/bin/flutter.bat') {
    $flutterCommand = 'C:/dev/flutter-3.32.8/bin/flutter.bat'
} else {
    $flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
}
$flutterVersion = (& $flutterCommand --version --machine | Out-String | ConvertFrom-Json).frameworkVersion
if ($flutterVersion -ne '3.32.8') {
    throw 'Android 6 requires Flutter 3.32.8. Pass -FlutterSdk or set MBN_FLUTTER_SDK to that SDK directory.'
}

New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null

Push-Location $projectRoot
try {
    $signingCredentialPath = Join-Path $projectRoot '.signing\credentials.xml'
    if (-not (Test-Path -LiteralPath $signingCredentialPath)) {
        throw 'Release signing credentials are missing. See docs/RELEASES_FA.md.'
    }
    $signingCredential = Import-Clixml -LiteralPath $signingCredentialPath
    $env:MBN_KEYSTORE_PATH = Join-Path $projectRoot '.signing\mbnmovie-release.jks'
    $env:MBN_KEY_ALIAS = $signingCredential.UserName
    $env:MBN_KEYSTORE_PASSWORD = $signingCredential.GetNetworkCredential().Password
    $env:MBN_KEY_PASSWORD = $env:MBN_KEYSTORE_PASSWORD
    Write-Host "Preparing MBNMovie $version..." -ForegroundColor Cyan
    Invoke-Flutter -Arguments @('pub', 'get')

    Write-Host 'Building Android for old and new phone CPUs...' -ForegroundColor Cyan
    Invoke-Flutter -Arguments @(
        'build',
        'apk',
        '--release',
        '--target-platform',
        'android-arm,android-arm64',
        '--split-per-abi'
    )

    $builtArm64Apk = Join-Path `
        $projectRoot `
        'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
    $builtLegacyApk = Join-Path `
        $projectRoot `
        'build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk'
    foreach ($builtApk in @($builtArm64Apk, $builtLegacyApk)) {
        if (-not (Test-Path -LiteralPath $builtApk -PathType Leaf)) {
            throw "Android output was not created at $builtApk"
        }
    }
    Copy-Item -LiteralPath $builtArm64Apk -Destination $androidOutput -Force
    Copy-Item -LiteralPath $builtLegacyApk -Destination $androidLegacyOutput -Force
    Install-AndroidPackage -ApkPath $androidOutput

    Write-Host 'Building Windows x64...' -ForegroundColor Cyan
    $legacyWindowsExecutable = Join-Path `
        $projectRoot `
        'build\windows\x64\runner\Release\mbnmovie.exe'
    if (Test-Path -LiteralPath $legacyWindowsExecutable -PathType Leaf) {
        Write-Host 'Removing stale mbnmovie.exe from the Windows build...' `
            -ForegroundColor Yellow
        Remove-Item -LiteralPath $legacyWindowsExecutable -Force
    }
    Invoke-Flutter -Arguments @('build', 'windows', '--release')

    $windowsBuild = Join-Path `
        $projectRoot `
        'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath $windowsBuild -PathType Container)) {
        throw "Windows output was not created at $windowsBuild"
    }
    if (Test-Path -LiteralPath $legacyWindowsExecutable -PathType Leaf) {
        Remove-Item -LiteralPath $legacyWindowsExecutable -Force
    }

    $windowsAppFolder = Join-Path $stagingRoot 'MBNMovie'
    New-Item -ItemType Directory -Path $windowsAppFolder -Force | Out-Null
    Copy-Item `
        -Path (Join-Path $windowsBuild '*') `
        -Destination $windowsAppFolder `
        -Recurse `
        -Force

    if (Test-Path -LiteralPath $windowsArchive -PathType Leaf) {
        Remove-Item -LiteralPath $windowsArchive -Force
    }

    $sevenZip = Find-SevenZip
    if ($null -ne $sevenZip) {
        Write-Host 'Compressing Windows package with 7-Zip level 9...' `
            -ForegroundColor Cyan
        & $sevenZip 'a' '-tzip' '-mx=9' '-mmt=on' $windowsArchive $windowsAppFolder
        if ($LASTEXITCODE -ne 0) {
            throw '7-Zip failed to create the Windows archive.'
        }
    }
    else {
        Write-Host 'Compressing Windows package at PowerShell Optimal level...' `
            -ForegroundColor Cyan
        Compress-Archive `
            -LiteralPath $windowsAppFolder `
            -DestinationPath $windowsArchive `
            -CompressionLevel Optimal
    }

    Write-Host ''
    Write-Host "Release $version is ready:" -ForegroundColor Green
    Write-Host "  Android new CPU (64-bit): $androidOutput"
    Write-Host "  Android old CPU (32-bit): $androidLegacyOutput"
    Write-Host "  Windows: $windowsArchive"
    Write-Host '  The Windows archive contains the MBNMovie application folder.'
}
finally {
    Remove-Item Env:MBN_KEYSTORE_PASSWORD, Env:MBN_KEY_PASSWORD, Env:MBN_KEY_ALIAS, Env:MBN_KEYSTORE_PATH -ErrorAction SilentlyContinue
    Pop-Location
    Remove-StagingDirectory
}
