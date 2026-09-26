[CmdletBinding()]
param(
    [string] $Device = 'windows',
    [switch] $ResolveDependencies
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSCommandPath
$configPath = Join-Path $projectRoot '.signing/api-config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw 'Private .signing/api-config.json is missing. Supply your authorized service client key as MBN_API_KEY in that ignored JSON file.'
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if (-not $config.PSObject.Properties['MBN_API_KEY'] -or
    [string]::IsNullOrWhiteSpace([string] $config.MBN_API_KEY)) {
    throw 'Private API configuration has no MBN_API_KEY.'
}
$flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
$flutterArguments = @('run', '-d', $Device, '--debug', "--dart-define-from-file=$configPath")
if (-not $ResolveDependencies) { $flutterArguments += '--no-pub' }
Push-Location -LiteralPath $projectRoot
try {
    # Native stderr may contain normal Flutter diagnostics, not a failed build.
    $ErrorActionPreference = 'Continue'
    & $flutterCommand @flutterArguments
    $flutterExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($flutterExitCode -ne 0) { throw "Flutter debug run failed (exit $flutterExitCode)." }
