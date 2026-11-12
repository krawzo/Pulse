param(
  [string]$ExePath,
  [int]$Cycles = 10,
  [switch]$UseCurrentProfile,
  [switch]$AccessibilityOptIn
)

$ErrorActionPreference = 'Stop'
if (-not $ExePath) {
  $projectRoot = Split-Path -Parent $PSScriptRoot
  $packaged = Join-Path (Split-Path -Parent $projectRoot) 'App\pulse_flutter.exe'
  $built = Join-Path $projectRoot 'build\windows\x64\runner\Release\pulse_flutter.exe'
  $ExePath = if (Test-Path -LiteralPath $packaged) { $packaged } else { $built }
}
$ExePath = (Resolve-Path -LiteralPath $ExePath).Path
if ($Cycles -lt 1) { throw 'Cycles must be positive.' }

Add-Type -AssemblyName UIAutomationClient
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PulseWindowProbe {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr window, int x, int y, int width, int height, bool repaint);
}
'@

$profiles = if ($UseCurrentProfile) { @('current') } else { @('empty', 'loaded') }
$probeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Pulse-r19-window-probe-{0}" -f [guid]::NewGuid().ToString('N'))
foreach ($profile in $profiles) {
  $startArguments = @{
    FilePath = $ExePath
    PassThru = $true
  }
  if ($AccessibilityOptIn) {
    $startArguments.ArgumentList = @('--enable-windows-accessibility')
  }
  if ($profile -ne 'current') {
    $appData = Join-Path $probeRoot $profile
    $catalogDirectory = Join-Path $appData 'PulseFlutter'
    New-Item -ItemType Directory -Path $catalogDirectory -Force | Out-Null
    if ($profile -eq 'loaded') {
      $tracks = for ($index = 0; $index -lt 200; $index++) {
        [ordered]@{
          id = "probe-$index"
          path = "C:\PulseProbe\track-$index.mp3"
          title = "Faixa sintética $index"
          artist = "Artista $($index % 11)"
          album = "Álbum $($index % 25)"
          sizeBytes = 1234
          modifiedAtMillis = 1
        }
      }
      $catalog = [ordered]@{
        rootPath = $null
        tracks = @($tracks)
        favoriteIds = @('probe-1', 'probe-7')
        playlists = @([ordered]@{ id = 'probe'; name = 'Playlist sintética'; trackIds = @('probe-1', 'probe-2') })
        scannedAtMillis = 1
      }
      $catalog | ConvertTo-Json -Depth 10 -Compress |
        Set-Content -LiteralPath (Join-Path $catalogDirectory 'library.json') -Encoding utf8
    }
    $startArguments.Environment = @{ LOCALAPPDATA = $appData }
  }

  $process = Start-Process @startArguments
  try {
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
      Start-Sleep -Milliseconds 50
      $process.Refresh()
      if ($process.HasExited -or $process.MainWindowHandle -ne 0) { break }
    }
    if ($process.HasExited -or $process.MainWindowHandle -eq 0) {
      throw "Pulse did not open a window for profile $profile."
    }
    $window = $process.MainWindowHandle
    [PulseWindowProbe]::MoveWindow($window, 100, 100, 740, 620, $true) | Out-Null
    $automation = [System.Windows.Automation.AutomationElement]::FromHandle($window)
    $condition = [System.Windows.Automation.Condition]::TrueCondition
    $null = $automation.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
    for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
      [PulseWindowProbe]::ShowWindow($window, 3) | Out-Null
      Start-Sleep -Milliseconds 350
      $process.Refresh()
      if ($process.HasExited) { throw "Pulse exited on maximize: $profile cycle $cycle, code $($process.ExitCode)." }
      $null = $automation.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
      [PulseWindowProbe]::ShowWindow($window, 9) | Out-Null
      [PulseWindowProbe]::MoveWindow($window, 100, 100, 740, 620, $true) | Out-Null
      Start-Sleep -Milliseconds 350
      $process.Refresh()
      if ($process.HasExited) { throw "Pulse exited on restore: $profile cycle $cycle, code $($process.ExitCode)." }
    }
    "profile=$profile cycles=$Cycles alive=true pid=$($process.Id) accessibilityOptIn=$AccessibilityOptIn"
  } finally {
    $process.Refresh()
    if (-not $process.HasExited) {
      $process.CloseMainWindow() | Out-Null
      if (-not $process.WaitForExit(5000)) { $process.Kill() }
    }
  }
}
