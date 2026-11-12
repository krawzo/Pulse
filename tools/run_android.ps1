$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$flutter = Join-Path $projectRoot 'tools\flutter\bin\flutter.bat'
$shortTemp = 'C:\PulseTmp'

foreach ($required in @($adb, $emulator, $flutter)) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "Componente Android ou Flutter não encontrado: $required"
  }
}

New-Item -ItemType Directory -Path $shortTemp -Force | Out-Null
$env:TEMP = $shortTemp
$env:TMP = $shortTemp
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=$shortTemp -Djava.io.tmpdir=$shortTemp"

$devices = & $adb devices
if (($devices -join "`n") -notmatch 'emulator-5554\s+device') {
  Start-Process -FilePath $emulator -ArgumentList @(
    '-avd', 'Pulse_Android_15', '-no-snapshot', '-gpu', 'host',
    '-feature', '-Vulkan', '-no-boot-anim'
  )
} else {
  $runningName = (& $adb -s emulator-5554 emu avd name) -join "`n"
  if ($runningName -notmatch 'Pulse_Android_15') {
    throw 'Feche o outro emulador antes de abrir o Pulse no Android 15.'
  }
}

$ready = $false
for ($attempt = 0; $attempt -lt 90; $attempt++) {
  $booted = & $adb -s emulator-5554 shell getprop sys.boot_completed 2>$null
  if ($booted -eq '1') {
    $ready = $true
    break
  }
  Start-Sleep -Seconds 2
}
if (-not $ready) {
  throw 'O emulador Android não terminou de iniciar.'
}

Push-Location $projectRoot
try {
  & $flutter run -d emulator-5554
} finally {
  Pop-Location
}
