# Creates a persistent personal release key. Private files are never committed.
$ErrorActionPreference = 'Stop'
$hcRoot = Split-Path -Parent $PSScriptRoot
$hcPropertiesPath = Join-Path $hcRoot 'android\key.properties'
if (Test-Path -LiteralPath $hcPropertiesPath) {
    Write-Output 'Existing release signing configuration preserved.'
    exit 0
}
$hcKeyDirectory = Join-Path $env:USERPROFILE '.android\healthcoach-signing'
New-Item -ItemType Directory -Force -Path $hcKeyDirectory | Out-Null
$hcKeyPath = Join-Path $hcKeyDirectory 'healthcoach-release.jks'
if (Test-Path -LiteralPath $hcKeyPath) { throw 'A release key already exists. Restore android/key.properties from your private backup instead of replacing the key.' }
$hcRandom = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($hcRandom)
$hcPassword = [Convert]::ToBase64String($hcRandom)
$hcKeytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
$env:HC_SIGNING_PASSWORD = $hcPassword
try {
    & $hcKeytool -genkeypair -keystore $hcKeyPath -storetype JKS -alias healthcoach -keyalg RSA -keysize 3072 -validity 10000 -storepass:env HC_SIGNING_PASSWORD -keypass:env HC_SIGNING_PASSWORD -dname 'CN=HealthCoach Personal App'
    if ($LASTEXITCODE -ne 0) { throw 'Key generation failed.' }
    $hcStorePath = $hcKeyPath.Replace('\', '/')
    @"
storePassword=$hcPassword
keyPassword=$hcPassword
keyAlias=healthcoach
storeFile=$hcStorePath
"@ | Set-Content -LiteralPath $hcPropertiesPath -Encoding utf8
    Write-Output "Personal signing key created in $hcKeyDirectory. Back up this folder and android/key.properties privately."
} finally {
    Remove-Item Env:\HC_SIGNING_PASSWORD -ErrorAction SilentlyContinue
    $hcPassword = $null
}
