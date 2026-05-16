$ErrorActionPreference='Continue'
function P($l,$v){ "{0,-34} {1}" -f $l, $v }
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
$pr=New-Object Security.Principal.WindowsPrincipal($id)
P 'whoami' $id.Name
P 'elevated(admin)' ($pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))
P 'hostname' $env:COMPUTERNAME
foreach($p in @(
 'C:\jacks\AI',
 'C:\jacks\AI\sunshine-virtual-monitor',
 'C:\jacks\AI\sunshine-virtual-monitor\roam',
 'C:\Users\jacks\Downloads\tools\MultiMonitorTool.exe',
 'C:\Users\jacks\sunshine\privacy-on.ps1',
 'C:\Users\jacks\sunshine\privacy-off.ps1',
 'C:\Program Files\Sunshine\config\sunshine.conf',
 'C:\Program Files\Sunshine\config\apps.json',
 'C:\VirtualDisplayDriver\vdd_settings.xml')){
  P "exists? $p" (Test-Path -LiteralPath $p)
}
$t=Get-ScheduledTask -TaskName 'RoamDisplayWatcher' -ErrorAction SilentlyContinue
P 'RoamDisplayWatcher task' ($(if($t){$t.State}else{'<not registered>'}))
$mmt='C:\Users\jacks\Downloads\tools\MultiMonitorTool.exe'
if(Test-Path $mmt){
  $csv="$env:TEMP\_roam_diag_scan.csv"
  & $mmt /scomma $csv | Out-Null; Start-Sleep -Milliseconds 500
  if(Test-Path $csv){
    "--- MultiMonitorTool live scan ---"
    Import-Csv $csv | Select-Object 'Name','Short Monitor ID','Monitor Name','Active','Primary','Resolution','Left-Top','Right-Bottom' |
      Format-Table -AutoSize | Out-String -Width 240
  }
}
"--- sunshine.conf (live) ---"
if(Test-Path 'C:\Program Files\Sunshine\config\sunshine.conf'){ Get-Content 'C:\Program Files\Sunshine\config\sunshine.conf' }
"--- privacy-on (deployed) ---"
if(Test-Path 'C:\Users\jacks\sunshine\privacy-on.ps1'){ Get-Content 'C:\Users\jacks\sunshine\privacy-on.ps1' }
"--- DONE ---"
