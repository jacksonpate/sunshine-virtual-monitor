# ELEVATED one-time: register the roam watcher as a logon scheduled task
# (runs in the interactive session, highest privileges, survives reboot), then start it.
$ErrorActionPreference='Continue'
$roam='C:\jacks\AI\sunshine-virtual-monitor\roam'
$res ="$roam\install-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $res -Append }
"=== ROAM-INSTALL START $(Get-Date -Format o) ===" | Set-Content $res
$me = "$env:USERDOMAIN\$env:USERNAME"
L "user=$me  elevated=$(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))"

$task='RoamDisplayWatcher'
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$roam\roam-watcher.ps1`""
$trg = New-ScheduledTaskTrigger -AtLogOn -User $me
$prn = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
        -MultipleInstances IgnoreNew
try {
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
  Register-ScheduledTask -TaskName $task -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
  L "scheduled task '$task' registered (AtLogOn, Interactive, Highest)"
} catch { L "ERR register: $_" }

# kill any stray instance, then start now for testing
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'roam-watcher\.ps1' } | ForEach-Object { try{Stop-Process -Id $_.ProcessId -Force}catch{} }
Start-Sleep 1
try { Start-ScheduledTask -TaskName $task; L 'task started' } catch { L "ERR start: $_" }
Start-Sleep 5
$running = [bool](Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'roam-watcher\.ps1' })
$st = (Get-ScheduledTask -TaskName $task -EA SilentlyContinue).State
L "task state=$st  watcher process running=$running"
if (Test-Path "$roam\roam.log") { L "--- roam.log tail ---"; Get-Content "$roam\roam.log" -Tail 6 | ForEach-Object { L "  $_" } }
L ("RESULT=" + $(if($running){'OK - watcher live. Test corners + desk input.'}else{'NOT RUNNING - see roam.log / above'}))
"=== ROAM-INSTALL END $(Get-Date -Format o) ===" | Tee-Object -FilePath $res -Append
