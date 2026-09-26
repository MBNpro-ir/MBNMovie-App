param([string]$Repository = 'MBNpro-ir/MBNMovie-App')
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot -Parent
$signingDirectory = Join-Path $projectDirectory '.signing'
$keyFile = Join-Path $signingDirectory 'mbnmovie-release.jks'
$settingsFile = Join-Path $signingDirectory 'credentials.xml'
if (Test-Path -LiteralPath $keyFile) { throw 'Signing key already exists. It must never be replaced.' }
$keytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
if (-not (Test-Path -LiteralPath $keytool)) { $keytool = (Get-Command keytool -ErrorAction Stop).Source }
New-Item -ItemType Directory -Path $signingDirectory -Force | Out-Null
$env:MBN_KEYSTORE_PASSWORD = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(36))
$env:MBN_KEY_PASSWORD = $env:MBN_KEYSTORE_PASSWORD
try {
    & $keytool -genkeypair -keystore $keyFile -storetype JKS -alias mbnmovie-release -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=MBNMovie, O=MBNpro-ir' -storepass:env MBN_KEYSTORE_PASSWORD -keypass:env MBN_KEY_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Signing key generation failed.' }
    # Windows DPAPI protects the password at rest for this Windows account.
    [PSCredential]::new('mbnmovie-release', (ConvertTo-SecureString $env:MBN_KEYSTORE_PASSWORD -AsPlainText -Force)) | Export-Clixml -LiteralPath $settingsFile
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($keyFile)) | gh secret set ANDROID_KEYSTORE_BASE64 --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw 'Keystore secret upload failed; keep local signing files.' }
    $env:MBN_KEYSTORE_PASSWORD | gh secret set ANDROID_KEYSTORE_PASSWORD --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw 'Password secret upload failed.' }
    $env:MBN_KEY_PASSWORD | gh secret set ANDROID_KEY_PASSWORD --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw 'Key password secret upload failed.' }
    'mbnmovie-release' | gh secret set ANDROID_KEY_ALIAS --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw 'Alias secret upload failed.' }
    Write-Host 'Dedicated signing key generated; encrypted local credentials and GitHub Secrets saved.'
} finally {
    Remove-Item Env:MBN_KEYSTORE_PASSWORD, Env:MBN_KEY_PASSWORD -ErrorAction SilentlyContinue
}
