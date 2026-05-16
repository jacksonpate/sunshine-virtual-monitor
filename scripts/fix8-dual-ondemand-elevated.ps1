# ELEVATED fix #8: dual second-monitor + on-demand.
#  Same as fix7's working setup but dd_configuration_option = ensure_active
#  (laptop stays the main screen during stream; VDD = extended 2nd monitor).
#  From the clean laptop-only baseline, auto-verify VDD STAYS off when idle
#  (the exact thing that failed with ensure_active before fix7's clean baseline).
$ErrorActionPreference='Continue'
$b='C:\jacks\AI\sunshine-virtual-monitor'
$log="$b\fix8-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $log -Append }
"=== FIX8 START $(Get-Date -Format o) ===" | Set-Content $log
$mt="$b\multimonitortool-x64\MultiMonitorTool.exe"
function Scan { & $mt /scomma "$b\_s8.csv" | Out-Null; Start-Sleep 1; Import-Csv "$b\_s8.csv" }
function VddActive { $v=(Scan)|?{$_.'Monitor Name' -match 'VDD|MTT'}|Select -First 1; if($v){$v.Active -eq 'Yes'}else{$false} }
function Topo { ($(Scan) | %{ "$($_.Name)[$($_.'Monitor Name')] act=$($_.Active) prim=$($_.Primary)" }) -join ' | ' }

# 1. Sunshine down, force clean laptop-only baseline
Stop-Service SunshineService -Force -EA SilentlyContinue
Start-Sleep 2
Get-Process sunshine,sunshinesvc -EA SilentlyContinue | %{ try{Stop-Process -Id $_.Id -Force}catch{} }
Start-Sleep 2
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class CCD { [DllImport("user32.dll")] public static extern int SetDisplayConfig(uint a,IntPtr b,uint c,IntPtr d,uint f); }
"@
[void][CCD]::SetDisplayConfig(0,[IntPtr]::Zero,0,[IntPtr]::Zero,(0x80 -bor 0x01))   # internal-only
Start-Sleep 4
$vr=(Scan)|?{$_.'Monitor Name' -match 'VDD|MTT'}|Select -First 1
if($vr -and $vr.Active -eq 'Yes'){ & $mt /disable $vr.Name; Start-Sleep 3 }
L "baseline (Sunshine DOWN): VDD active=$(VddActive)  topo=$(Topo)"

# 2. config: ensure_active, everything else identical to fix7
$conf='C:\Program Files\Sunshine\config\sunshine.conf'
Copy-Item $conf "$conf.bak-fix8-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
$VDD_ID='{9acddf6d-43cc-576e-9aff-0c5fc80b4cc8}'
$desired=@(
  "output_name = $VDD_ID"
  'dd_configuration_option = ensure_active'
  'dd_resolution_option = auto'
  'dd_refresh_rate_option = auto'
  'dd_hdr_option = auto'
  'dd_config_revert_delay = 3000'
  'dd_config_revert_on_disconnect = enabled'
)
$keys='output_name','dd_configuration_option','dd_resolution_option','dd_refresh_rate_option','dd_hdr_option','dd_config_revert_delay','dd_config_revert_on_disconnect','global_prep_cmd'
$kept = Get-Content $conf | ?{ $line=$_; -not ($keys | ?{ $line -match ("^\s*"+[regex]::Escape($_)+"\s*=") }) }
Set-Content -Path $conf -Value (@($kept|?{$_.Trim() -ne ''}) + $desired) -Encoding ASCII
L "sunshine.conf -> dd_configuration_option = ensure_active (laptop stays main, VDD = 2nd)"

# 3. start Sunshine, watch idle 35s: VDD must STAY inactive (this is the make-or-break)
Start-Service SunshineService
$up=$false
for($i=0;$i -lt 20;$i++){ Start-Sleep 2; if((Get-Process sunshine -EA SilentlyContinue) -and (Get-NetTCPConnection -State Listen -EA SilentlyContinue|? LocalPort -in 47984,47989,48010)){ $up=$true; break } }
L "Sunshine listener=$(if($up){'UP'}else{'DOWN'})"
$reactivated=$false
for($t=1;$t -le 7;$t++){ Start-Sleep 5; if(VddActive){ $reactivated=$true; L "  [t+$($t*5)s idle] VDD ACTIVE (ensure_active forces 24/7 - dual+on-demand NOT possible)"; break } else { L "  [t+$($t*5)s idle] VDD inactive (good)" } }
$crash=(Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=(Get-Date).AddMinutes(-2)} -EA SilentlyContinue|? Message -match 'Sunshine'|Measure-Object).Count
L "crashes2min=$crash finalTopo=$(Topo)"
if($up -and -not $reactivated -and $crash -eq 0){
  L "RESULT=GOOD - idle stays laptop-only with ensure_active. Now TEST: connect should keep laptop ON + add VDD 2nd (iPad streams VDD); quit should drop VDD, keep laptop."
} else {
  L "RESULT=ENSURE_ACTIVE_IS_24/7 - revert to ensure_only_display recommended (dual + true on-demand not supported by Sunshine on this box)."
}
"=== FIX8 END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
