param([Parameter(Mandatory = $true)][string]$Bundle)
$ErrorActionPreference = 'Stop'
$expected = '04E4D27DC385DC18DDD93FBE69C75E635B864F3C6EC53A9122DF54C2F7842F4A'
$actual = (Get-FileHash -LiteralPath (Join-Path $Bundle 'libmpv-2.dll') -Algorithm SHA256).Hash
if ($actual -ne $expected) { throw "Windows playback core does not match the tested build: $actual" }
foreach ($name in @('MPV-NOTICE.txt', 'MPV-LICENSE.GPL.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Bundle $name))) { throw "Missing native playback notice: $name" }
}
Write-Output 'Windows playback core SHA256 and notices verified.'
