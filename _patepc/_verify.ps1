$ErrorActionPreference='Continue'
$roam='C:\jacks\AI\sunshine-virtual-monitor\roam'
"=== deployed files ==="
Get-ChildItem $roam -Filter *.ps1 | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String
"=== scheduled task ==="
$t=Get-ScheduledTask -TaskName RoamDisplayWatcher -ErrorAction SilentlyContinue
if($t){
  "State            : $($t.State)"
  "RunLevel         : $($t.Principal.RunLevel)"
  "LogonType        : $($t.Principal.LogonType)"
  "Trigger          : $($t.Triggers[0].CimClass.CimClassName)"
  $a=$t.Actions[0]
  "Action.Execute   : $($a.Execute)"
  "Action.Arguments : $($a.Arguments)"
} else { "RoamDisplayWatcher NOT registered" }
"=== startup launcher ==="
$cmd=Join-Path ([Environment]::GetFolderPath('Startup')) 'RoamDisplayWatcher.cmd'
if(Test-Path $cmd){ Get-Content $cmd } else { "MISSING: $cmd" }
"=== watcher process (expect NONE - not started during sleep) ==="
$p=Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'roam-watcher\.ps1' }
if($p){ "RUNNING pid $($p.ProcessId)  <-- unexpected" } else { "not running (correct)" }
"=== read-only helper smoke test (no topology change) ==="
. "$roam\roam-lib.ps1"
$m = Get-Mons
"monitors seen: " + ($m | ForEach-Object { $_.'Short Monitor ID' + '(' + $_.'Short Monitor ID' + ',act=' + $_.Active + ')' } | Where-Object {$_} ) -join '  '
"raw rows:"
$m | Select-Object 'Name','Short Monitor ID','Monitor Name','Active','Primary','Left-Top','Right-Bottom' | Format-Table -AutoSize | Out-String -Width 220
"Vdd-Row(MTT1337) : " + $(($v=Vdd-Row $m); if($v){ "$($v.'Monitor Name') active=$($v.Active) LT=$($v.'Left-Top') RB=$($v.'Right-Bottom')" } else {'<null>'})
"Vdd-Active       : " + (Vdd-Active)
"AnyPhys-Active   : " + (AnyPhys-Active)
"AllPhys-Active   : " + (AllPhys-Active)
"Session-Live     : " + (Session-Live)
"--- predicted initial watcher state ---"
if (AnyPhys-Active) { 'ALL  (a physical monitor is active)' }
elseif ((Vdd-Active) -and (Session-Live)) { 'AWAY (VDD only + live session)' }
else { 'ALL  (fallback)' }
"=== DONE ==="
