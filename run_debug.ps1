param([string]$Device = 'windows')

$credentials = Join-Path $PSScriptRoot 'debug_auth.json'
if (-not (Test-Path -LiteralPath $credentials)) {
    Write-Error 'Copy debug_auth.example.json to debug_auth.json and enter the test account credentials.'
    exit 1
}
$config = Get-Content -LiteralPath $credentials -Raw | ConvertFrom-Json
if (-not $config.MBN_DEBUG_IDENTIFIER -or -not $config.MBN_DEBUG_PASSWORD) {
    Write-Error 'debug_auth.json must contain MBN_DEBUG_IDENTIFIER and MBN_DEBUG_PASSWORD.'
    exit 1
}

Push-Location -LiteralPath $PSScriptRoot
try {
    flutter run -d $Device --dart-define-from-file=debug_auth.json
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
