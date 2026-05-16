# ELEVATED fix #2: remove the broken global_prep_cmd (its exit-1 kills the stream).
# VDD is already the sole active display, so Sunshine will just capture it. No script.
$ErrorActionPreference='Continue'
$b='C:\jacks\AI\sunshine-virtual-monitor'
$log="$b\fix2-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $log -Append }
"=== FIX2 START $(Get-Date -Format o) ===" | Set-Content $log
L ("elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))

$conf='C:\Program Files\Sunshine\config\sunshine.conf'
Copy-Item $conf "$conf.bak-fix2-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force

# strip global_prep_cmd entirely
$lines = @(Get-Content $conf | Where-Object { $_ -notmatch '^\s*global_prep_cmd\s*=' })
Set-Content -Path $conf -Value $lines -Encoding ASCII
$still = (Get-Content $conf | Where-Object { $_ -match 'global_prep_cmd' }).Count
L "global_prep_cmd removed (remaining matches=$still). conf lines=$($lines.Count)"

# make sure the VDD is enabled + is the sole active display (it already is; enforce)
$vdd = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -like 'Virtual Display*' } | Select-Object -First 1
if ($vdd -and $vdd.Status -ne 'OK') { try { $vdd | Enable-PnpDevice -Confirm:$false; L "VDD enabled" } catch { L "ERR enable: $_" } }
L "VDD status=$((Get-PnpDevice -InstanceId $vdd.InstanceId).Status)"
$mt="$b\multimonitortool-x64\MultiMonitorTool.exe"
& $mt /scomma "$b\_mons2.csv"; Start-Sleep 1
$mons = Import-Csv "$b\_mons2.csv"
$vddMon = $mons | Where-Object { $_.'Monitor Name' -like '*VDD*' -or $_.'Monitor Name' -like '*MTT*' } | Select-Object -First 1
if ($vddMon) {
  & $mt /SetPrimary $vddMon.Name
  L "VDD primary set on $($vddMon.Name) ($($vddMon.'Monitor Name'))"
}
L ("topology: " + (($mons | ForEach-Object { "$($_.Name)[$($_.'Monitor Name')] act=$($_.Active) prim=$($_.Primary)" }) -join ' | '))

# restart Sunshine, verify listener + no crash
try { Stop-Service SunshineService -Force -EA SilentlyContinue } catch {}
Start-Sleep 2
Get-Process sunshine,sunshinesvc -EA SilentlyContinue | ForEach-Object { try{Stop-Process -Id $_.Id -Force}catch{} }
Start-Sleep 2
Start-Service SunshineService
L "SunshineService restarted"
$ok=$false
for($i=0;$i -lt 20;$i++){
  Start-Sleep 2
  $proc=Get-Process sunshine -EA SilentlyContinue
  $port=Get-NetTCPConnection -State Listen -EA SilentlyContinue | Where-Object LocalPort -in 47984,47989,48010,47990
  if($proc -and $port){ $ok=$true; break }
}
$port=Get-NetTCPConnection -State Listen -EA SilentlyContinue | Where-Object LocalPort -in 47984,47989,48010,47990
L ("ports=" + (($port.LocalPort|Sort-Object -Unique) -join ',') + "  RESULT=" + $(if($ok){'UP - reconnect Moonlight now'}else{'DOWN'}))
$cr=Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=(Get-Date).AddMinutes(-2)} -EA SilentlyContinue | Where-Object Message -match 'Sunshine'
L ("Sunshine crashes last 2min=" + (($cr|Measure-Object).Count))
"=== FIX2 END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
