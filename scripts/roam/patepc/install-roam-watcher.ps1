# install-roam-watcher.ps1  (Pate-PC) - arm the roam watcher to autostart.
#
# Works WITHOUT elevation: registers a per-user AtLogon scheduled task
# 'RoamDisplayWatcher' (RunLevel Limited - MMT /enable/disable, CCD
# SetDisplayConfig and the WH_*_LL hooks all work at Limited in the user's own
# interactive session; the upstream clone used Highest only defensively).
# -MultipleInstances IgnoreNew + a real Global\RoamWatcherSingleton mutex in
# the watcher keep it strictly single-instance.
#
# By default it does NOT start the watcher now (-Start to override). Starting it
# rebuilds the display topology, which would disturb sleep-mode dim overlays.
# It will come up on the next logon regardless.
[CmdletBinding()]
param([switch]$Start)
$ErrorActionPreference='Continue'
$roam = 'C:\jacks\AI\sunshine-virtual-monitor\roam'
$res  = "$roam\install-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $res -Append }
if (Test-Path "$PSScriptRoot\roam-lib.ps1") { . "$PSScriptRoot\roam-lib.ps1" }
"=== ROAM-INSTALL START $(Get-Date -Format o) ===" | Set-Content $res

$me   = "$env:USERDOMAIN\$env:USERNAME"
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
L "user=$me  elevated=$elev  roam=$roam"
if (-not (Test-Path "$roam\roam-watcher.ps1")) { L "FATAL: $roam\roam-watcher.ps1 missing - run deploy-patepc.ps1 first"; return }

# --- 1. scheduled task (best effort at the privilege level we have) ---
$task = 'RoamDisplayWatcher'
$run  = if ($elev) { 'Highest' } else { 'Limited' }
$act  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$roam\roam-watcher.ps1`""
$trg  = New-ScheduledTaskTrigger -AtLogOn -User $me
$prn  = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel $run
$set  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
          -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -RestartCount 3 `
          -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
try {
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
  Register-ScheduledTask -TaskName $task -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
  L "scheduled task registered (AtLogon, Interactive, RunLevel=$run)"
} catch { L "ERROR register task failed: $($_.Exception.Message)" }

# --- 2. cleanup: remove the legacy Startup-folder launcher if a prior install
#         wrote one (the scheduled task is the single autostart mechanism now) ---
try {
  $legacy = Join-Path ([Environment]::GetFolderPath('Startup')) 'RoamDisplayWatcher.cmd'
  if (Test-Path $legacy) { Remove-Item -LiteralPath $legacy -Force; L "removed legacy startup launcher: $legacy" }
} catch { L "WARN startup-launcher cleanup: $($_.Exception.Message)" }

# --- 3. optionally start now (off by default - sleep-mode safe) ---
if ($Start) {
  if (Get-Command Get-WatcherProcs -EA SilentlyContinue) { Get-WatcherProcs | ForEach-Object { try{Stop-Process -Id $_.ProcessId -Force}catch{} } }
  Start-Sleep 1
  try { Start-ScheduledTask -TaskName $task; L 'task started' }
  catch {
    L "task start failed, launching directly: $($_.Exception.Message)"
    Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$roam\roam-watcher.ps1`"" -WindowStyle Hidden
  }
  Start-Sleep 5
  $wp = if (Get-Command Get-WatcherProcs -EA SilentlyContinue) { Get-WatcherProcs }
  $running = [bool]$wp
  L ("RESULT=" + $(if($running){'OK - watcher live. Test iPad corners.'}else{'NOT RUNNING - see roam.log'}))
} else {
  L 'RESULT=ARMED (not started - will come up at next logon; run start-roam-watcher.ps1 when at the desk & streaming)'
}
$st = (Get-ScheduledTask -TaskName $task -EA SilentlyContinue).State
L "scheduled task state=$st"
"=== ROAM-INSTALL END $(Get-Date -Format o) ===" | Tee-Object -FilePath $res -Append
