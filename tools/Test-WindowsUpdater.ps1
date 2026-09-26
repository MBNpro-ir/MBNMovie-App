$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot -Parent
$cmake = 'C:\Program Files\Microsoft Visual Studio\18\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
if (-not (Test-Path -LiteralPath $cmake)) { $cmake = (Get-Command cmake -ErrorAction Stop).Source }
$buildDirectory = Join-Path $projectDirectory 'build\updater-tests'
& $cmake -S (Join-Path $projectDirectory 'test\native') -B $buildDirectory
if ($LASTEXITCODE) { throw 'Native test configuration failed.' }
& $cmake --build $buildDirectory --config Release
if ($LASTEXITCODE) { throw 'Native test compilation failed.' }
$runDirectory = Join-Path $buildDirectory ('run-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory | Out-Null

foreach ($scenario in @('success', 'rollback', 'incomplete')) {
    $scenarioDirectory = Join-Path $runDirectory $scenario
    $installDirectory = Join-Path $scenarioDirectory 'installed'
    $stageDirectory = Join-Path $scenarioDirectory 'stage\MBNMovie'
    New-Item -ItemType Directory -Path $installDirectory, (Join-Path $stageDirectory 'data') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $buildDirectory 'old\mbnmovie.exe') -Destination $installDirectory
    Copy-Item -LiteralPath (Join-Path $buildDirectory 'new\mbnmovie.exe') -Destination $stageDirectory
    # Generated test data, confined to this unique test directory.
    [IO.File]::WriteAllText((Join-Path $stageDirectory 'data\app.so'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $stageDirectory 'flutter_windows.dll'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $installDirectory 'keep-user-file.txt'), 'must survive')
    if ($scenario -eq 'rollback') { Copy-Item -LiteralPath (Join-Path $buildDirectory 'fail\mbnmovie.exe') -Destination (Join-Path $stageDirectory 'mbnmovie.exe') -Force }
    if ($scenario -eq 'incomplete') {
        $missingFixture = Join-Path $stageDirectory 'data\app.so'
        Remove-Item -LiteralPath $missingFixture
    }
    $readyFile = Join-Path $scenarioDirectory 'stage\ready'
    $fixture = Start-Process -FilePath (Join-Path $installDirectory 'mbnmovie.exe') -ArgumentList @('--wait', ('"' + $readyFile + '"')) -WindowStyle Hidden -PassThru
    try {
        $helper = Start-Process -FilePath (Join-Path $buildDirectory 'Release\updater_test.exe') -ArgumentList @('--apply', $fixture.Id, ('"' + $installDirectory + '"'), ('"' + $stageDirectory + '"'), ('"' + $readyFile + '"')) -WindowStyle Hidden -PassThru
        if (-not $helper.WaitForExit(45000)) { throw 'Updater smoke test timed out.' }
        if ((Get-Content -Raw -LiteralPath (Join-Path $installDirectory 'keep-user-file.txt')) -ne 'must survive') { throw 'User file was changed.' }
        if ($scenario -eq 'success') {
            if ($helper.ExitCode -ne 0 -or (Get-Content -Raw -LiteralPath (Join-Path $installDirectory 'run-marker.txt')) -ne 'new') { throw 'Update/relaunch failed.' }
        } elseif ($scenario -eq 'rollback') {
            if ($helper.ExitCode -eq 0 -or (Get-Content -Raw -LiteralPath (Join-Path $installDirectory 'run-marker.txt')) -ne 'old') { throw 'Rollback/relaunch failed.' }
        } else {
            if ($helper.ExitCode -eq 0 -or (Test-Path -LiteralPath $readyFile)) { throw 'Incomplete bundle was accepted.' }
            if ($fixture.HasExited) { throw 'Incomplete bundle closed the current app.' }
        }
        Write-Host "PASS: $scenario"
    } finally {
        # Only test processes running exact executables in this generated fixture.
        Get-Process -Name mbnmovie -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $installDirectory 'mbnmovie.exe') } | Stop-Process -Force
    }
}
Write-Host "Evidence retained in $runDirectory"
