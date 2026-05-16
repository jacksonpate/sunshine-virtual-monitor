$ErrorActionPreference='Continue'
$roam='C:\jacks\AI\sunshine-virtual-monitor\roam'; $res="$roam\restart-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $res -Append }
"=== RESTART $(Get-Date -Format o) ===" | Set-Content $res
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'roam-watcher\.ps1' } | ForEach-Object { try{Stop-Process -Id $_.ProcessId -Force; L "killed pid $($_.ProcessId)"}catch{ L "kill err $_" } }
Start-Sleep 2
try { Stop-ScheduledTask -TaskName RoamDisplayWatcher -EA SilentlyContinue } catch {}
Start-Sleep 1
try { Start-ScheduledTask -TaskName RoamDisplayWatcher; L 'task started' } catch { L "start err $_" }
Start-Sleep 6
$p = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'roam-watcher\.ps1' }
L ("watcher running=" + $(if($p){"yes pid $($p.ProcessId)"}else{'NO'}))
if (Test-Path "$roam\roam.log") { Get-Content "$roam\roam.log" -Tail 3 | ForEach-Object { L "  $_" } }
"=== RESTART END ===" | Tee-Object -FilePath $res -Append
