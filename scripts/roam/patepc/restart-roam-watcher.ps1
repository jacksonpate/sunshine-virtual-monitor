# restart-roam-watcher.ps1  (Pate-PC) - reload after editing roam-*.ps1.
# Kills the running watcher and starts a fresh one. Run only when at the desk
# / streaming (rebuilds topology). Mutex-guarded.
$ErrorActionPreference='Continue'
$roam = 'C:\jacks\AI\sunshine-virtual-monitor\roam'
$res  = "$roam\restart-result.txt"
. "$PSScriptRoot\roam-lib.ps1"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $res -Append }
"=== RESTART $(Get-Date -Format o) ===" | Set-Content $res
Get-WatcherProcs |
  ForEach-Object { try{ Stop-Process -Id $_.ProcessId -Force; L "killed pid $($_.ProcessId)" }catch{ L "kill err $_" } }
Start-Sleep 2
try { Stop-ScheduledTask -TaskName RoamDisplayWatcher -EA SilentlyContinue } catch {}
Start-Sleep 1
try { Start-ScheduledTask -TaskName RoamDisplayWatcher -EA Stop; L 'task started' }
catch {
  Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$roam\roam-watcher.ps1`"" -WindowStyle Hidden
  L "started directly ($($_.Exception.Message))"
}
Start-Sleep 6
$p = Get-WatcherProcs
L ("watcher running=" + $(if($p){"yes pid $($p.ProcessId)"}else{'NO'}))
if (Test-Path "$roam\roam.log") { Get-Content "$roam\roam.log" -Tail 3 | ForEach-Object { L "  $_" } }
"=== RESTART END ===" | Tee-Object -FilePath $res -Append
