[CmdletBinding()]
param(
    [string] $Device = '7bce7cbc',
    [switch] $ResolveDependencies
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSCommandPath
$debugRunner = Join-Path $projectRoot 'Run-MBNMovie-Debug.ps1'
$configPath = Join-Path $projectRoot '.signing/api-config.json'

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw 'Private .signing/api-config.json is missing. Android debug cannot access the catalog without MBN_API_KEY.'
}

Write-Host "Launching MBNMovie Android debug on $Device with the ignored local API configuration..." -ForegroundColor Cyan
& $debugRunner -Device $Device -ResolveDependencies:$ResolveDependencies
if ($LASTEXITCODE -ne 0) {
    throw "Android debug runner failed (exit $LASTEXITCODE)."
}
