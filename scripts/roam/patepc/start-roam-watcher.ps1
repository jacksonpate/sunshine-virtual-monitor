# start-roam-watcher.ps1  (Pate-PC) - start the watcher NOW.
# Run this when you are at the desk and streaming (NOT during sleep mode - it
# rebuilds display topology). Mutex-guarded, so it is safe if one is already up.
$ErrorActionPreference='Continue'
$roam = 'C:\jacks\AI\sunshine-virtual-monitor\roam'
$already = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'roam-watcher\.ps1' }
if ($already) { "watcher already running (pid $($already.ProcessId))"; return }
try { Start-ScheduledTask -TaskName RoamDisplayWatcher -EA Stop; "started via scheduled task" }
catch {
  Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$roam\roam-watcher.ps1`"" -WindowStyle Hidden
  "started directly (scheduled task unavailable: $($_.Exception.Message))"
}
Start-Sleep 5
$p = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'roam-watcher\.ps1' }
("watcher running=" + $(if($p){"yes pid $($p.ProcessId)"}else{'NO - see roam.log'}))
if (Test-Path "$roam\roam.log") { '--- roam.log tail ---'; Get-Content "$roam\roam.log" -Tail 6 }
