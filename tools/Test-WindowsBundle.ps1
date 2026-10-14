$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual C++ compiler is required' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$testRoot = Join-Path $env:TEMP ('mbn-bundle-test-' + [guid]::NewGuid().ToString('N'))
$bundle = Join-Path $testRoot 'برنامه تست با فاصله'
$assets = Join-Path $bundle 'data\flutter_assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
foreach ($path in @('flutter_windows.dll','data\icudtl.dat','data\flutter_assets\AssetManifest.bin')) {
  Set-Content -LiteralPath (Join-Path $bundle $path) -Value 'test'
}
$source = Join-Path $repo 'windows\runner\tests\app_bundle_test.cpp'
$exe = Join-Path $bundle 'bundle-test.exe'
$obj = Join-Path $testRoot 'bundle-test.obj'
& cmd.exe /d /c "call `"$vcvars`" >nul && cl /nologo /EHsc /std:c++17 /utf-8 `"$source`" /Fe:`"$exe`" /Fo:`"$obj`""
if ($LASTEXITCODE -ne 0) { throw 'Native bundle test compilation failed' }
& $exe
if ($LASTEXITCODE -ne 0) { throw "Native bundle test failed ($LASTEXITCODE)" }

