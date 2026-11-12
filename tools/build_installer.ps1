$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*(?<name>\d+\.\d+\.\d+)\+(?<build>\d+)\s*$')
if (-not $versionMatch.Success) { throw 'Version name and build number are missing from pubspec.yaml.' }
$versionName = $versionMatch.Groups['name'].Value
$buildNumber = $versionMatch.Groups['build'].Value

$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$exe = Join-Path $releaseDir 'pulse_flutter.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Windows Release build is missing. Run tools\build_windows.ps1 first.' }

$installerCandidates = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
  'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  'C:\Program Files\Inno Setup 6\ISCC.exe'
)
$compiler = $installerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) { throw 'Inno Setup 6 compiler (ISCC.exe) was not found.' }

$generatedPlugins = Get-Content -LiteralPath (Join-Path $projectRoot 'windows\flutter\generated_plugins.cmake') -Raw
$pluginsMatch = [regex]::Match($generatedPlugins, 'list\(APPEND FLUTTER_PLUGIN_LIST(?<plugins>.*?)\)', 'Singleline')
if (-not $pluginsMatch.Success) { throw 'Could not read the Windows plugin list.' }
$pluginDlls = @($pluginsMatch.Groups['plugins'].Value -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { "${_}_plugin.dll" })
$files = @('pulse_flutter.exe', 'flutter_windows.dll', 'libmpv-2.dll') + $pluginDlls
if (Test-Path -LiteralPath (Join-Path $releaseDir 'native_assets.json')) {
  $files += 'native_assets.json'
}

$stage = Join-Path $projectRoot ("build\installer\staging-$versionName-$buildNumber-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
foreach ($name in $files) {
  $source = Join-Path $releaseDir $name
  if (-not (Test-Path -LiteralPath $source)) { throw "Release payload is missing: $name" }
  Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name) -ErrorAction Stop
}
Copy-Item -LiteralPath (Join-Path $releaseDir 'data') -Destination $stage -Recurse -ErrorAction Stop

$outputDir = Join-Path $projectRoot 'artifacts'
$icon = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
$script = Join-Path $PSScriptRoot 'pulse_installer.iss'
& $compiler "/DAppVersion=$versionName" "/DAppBuild=$buildNumber" "/DSourceDir=$stage" "/DOutputDir=$outputDir" "/DIconPath=$icon" $script
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }

$installer = Join-Path $outputDir "Pulse-Desktop-Instalador-v$versionName-build$buildNumber.exe"
if (-not (Test-Path -LiteralPath $installer)) { throw 'Installer was not generated.' }
Write-Output $installer
