$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
$match = [regex]::Match($pubspec, '(?m)^version:\s*(?<version>\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\+(?<build>\d+)\s*$')
if (-not $match.Success) { throw 'Não foi possível ler version: name+build de pubspec.yaml.' }

$bundledFlutter = Join-Path $projectRoot 'tools\flutter\bin\flutter.bat'
$flutter = if (Test-Path -LiteralPath $bundledFlutter) {
  $bundledFlutter
} else {
  (Get-Command flutter -ErrorAction Stop).Source
}

$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:\Temp'
New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null

Push-Location $projectRoot
try {
  & $flutter build apk --debug --target-platform android-arm,android-arm64,android-x64 --no-pub "--dart-define=PULSE_BUILD_NAME=$($match.Groups['version'].Value)" "--dart-define=PULSE_BUILD_NUMBER=$($match.Groups['build'].Value)"
  if ($LASTEXITCODE -ne 0) { throw "Flutter Android build falhou com código $LASTEXITCODE." }
} finally {
  Pop-Location
}
