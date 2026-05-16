# ELEVATED fix #7: true on-demand VDD via ensure_only_display.
#  - Sunshine STOPPED, baseline forced laptop-only, verify VDD stays off with Sunshine down
#  - dd_configuration_option = ensure_only_display (session-scoped; reverts on disconnect)
#  - start Sunshine, verify VDD STAYS inactive while idle (the key proof)
$ErrorActionPreference='Continue'
$b='C:\jacks\AI\sunshine-virtual-monitor'
$log="$b\fix7-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $log -Append }
"=== FIX7 START $(Get-Date -Format o) ===" | Set-Content $log
$mt="$b\multimonitortool-x64\MultiMonitorTool.exe"
function Scan { & $mt /scomma "$b\_s7.csv" | Out-Null; Start-Sleep 1; Import-Csv "$b\_s7.csv" }
function VddActive { $r=Scan; $v=$r|?{$_.'Monitor Name' -match 'VDD|MTT'}|Select -First 1; if($v){$v.Active -eq 'Yes'}else{$false} }
function Topo { ($(Scan) | %{ "$($_.Name)[$($_.'Monitor Name')] act=$($_.Active) prim=$($_.Primary)" }) -join ' | ' }

# 1. stop Sunshine so it can't force the VDD active
Stop-Service SunshineService -Force -EA SilentlyContinue
Start-Sleep 2
Get-Process sunshine,sunshinesvc -EA SilentlyContinue | %{ try{Stop-Process -Id $_.Id -Force}catch{} }
Start-Sleep 2
L "Sunshine stopped. topo=$(Topo)"

# 2. force baseline laptop-only (CCD internal-only) and verify it holds with Sunshine DOWN
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class CCD { [DllImport("user32.dll")] public static extern int SetDisplayConfig(uint a,IntPtr b,uint c,IntPtr d,uint f); }
"@
$rc=[CCD]::SetDisplayConfig(0,[IntPtr]::Zero,0,[IntPtr]::Zero,(0x80 -bor 0x01))   # SDC_APPLY|TOPOLOGY_INTERNAL
L "SetDisplayConfig(INTERNAL-ONLY) rc=$rc"
Start-Sleep 4
$vddRow = (Scan)|?{$_.'Monitor Name' -match 'VDD|MTT'}|Select -First 1
if($vddRow -and $vddRow.Active -eq 'Yes'){ L "VDD still active; MMT /disable $($vddRow.Name)"; & $mt /disable $vddRow.Name; Start-Sleep 3 }
$idleHoldsWithSunshineDown = -not (VddActive)
L "baseline (Sunshine DOWN): VDD active=$(VddActive)  topo=$(Topo)"

# 3. switch to ensure_only_display (session-scoped) keeping the rest
$conf='C:\Program Files\Sunshine\config\sunshine.conf'
Copy-Item $conf "$conf.bak-fix7-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
$VDD_ID='{9acddf6d-43cc-576e-9aff-0c5fc80b4cc8}'
$desired=@(
  "output_name = $VDD_ID"
  'dd_configuration_option = ensure_only_display'
  'dd_resolution_option = auto'
  'dd_refresh_rate_option = auto'
  'dd_hdr_option = auto'
  'dd_config_revert_delay = 3000'
  'dd_config_revert_on_disconnect = enabled'
)
$keys='output_name','dd_configuration_option','dd_resolution_option','dd_refresh_rate_option','dd_hdr_option','dd_config_revert_delay','dd_config_revert_on_disconnect','global_prep_cmd'
$kept = Get-Content $conf | ?{ $line=$_; -not ($keys | ?{ $line -match ("^\s*"+[regex]::Escape($_)+"\s*=") }) }
Set-Content -Path $conf -Value (@($kept|?{$_.Trim() -ne ''}) + $desired) -Encoding ASCII
L "sunshine.conf -> dd_configuration_option = ensure_only_display"

# 4. start Sunshine, then watch idle for ~30s: VDD must STAY inactive
Start-Service SunshineService
$up=$false
for($i=0;$i -lt 20;$i++){ Start-Sleep 2; if((Get-Process sunshine -EA SilentlyContinue) -and (Get-NetTCPConnection -State Listen -EA SilentlyContinue|? LocalPort -in 47984,47989,48010)){ $up=$true; break } }
L "Sunshine listener=$(if($up){'UP'}else{'DOWN'})"
$reactivated=$false
for($t=0;$t -lt 6;$t++){ Start-Sleep 5; if(VddActive){ $reactivated=$true; L "  [t+$([int]($t*5+5))s idle] VDD ACTIVE (bad)"; break } else { L "  [t+$([int]($t*5+5))s idle] VDD inactive (good)" } }
$crash=(Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=(Get-Date).AddMinutes(-2)} -EA SilentlyContinue|? Message -match 'Sunshine'|Measure-Object).Count
Get-Content 'C:\Program Files\Sunshine\config\sunshine.log' | Select-String "config: 'dd_configuration_option'" | Select -Last 1 | %{ L ("  "+$_.Line.Substring($_.Line.IndexOf('config:'))) }
L "crashes2min=$crash  finalTopo=$(Topo)"
L ("RESULT=" + $(if($up -and -not $reactivated -and $crash -eq 0){'OK - VDD stays OFF when idle. Connect=VDD only (laptop sleeps), quit=laptop back+VDD gone'}else{'PROBLEM - VDD reactivated at idle or Sunshine issue; see log'}))
"=== FIX7 END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
