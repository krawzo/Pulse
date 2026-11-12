$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
$match = [regex]::Match($pubspec, '(?m)^version:\s*(?<version>\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?:\+(?<build>\d+))?\s*$')
if (-not $match.Success) {
  throw 'Não foi possível ler version: name+build de pubspec.yaml.'
}

$versionName = $match.Groups['version'].Value
$buildNumber = if ($match.Groups['build'].Success) { $match.Groups['build'].Value } else { '1' }
$bundledFlutter = Join-Path $projectRoot 'tools\flutter\bin\flutter.bat'
$flutter = if (Test-Path -LiteralPath $bundledFlutter) {
  $bundledFlutter
} else {
  $command = Get-Command flutter -ErrorAction Stop
  $command.Source
}
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

Push-Location $projectRoot
try {
  & $flutter build windows --release "--dart-define=PULSE_BUILD_NAME=$versionName" "--dart-define=PULSE_BUILD_NUMBER=$buildNumber"
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter Release build falhou com código $LASTEXITCODE."
  }
} finally {
  Pop-Location
}
