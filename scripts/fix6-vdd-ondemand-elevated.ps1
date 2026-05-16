# ELEVATED fix #6: make the VDD ON-DEMAND only (not 24/7).
#  - idle baseline = laptop-only (CCD internal-only topology; persists reboot)
#  - VDD pnp device stays ENABLED so Sunshine can re-activate it per stream
#  - sunshine.conf: dd_config_revert_on_disconnect = enabled (revert to baseline on quit)
$ErrorActionPreference='Continue'
$b='C:\jacks\AI\sunshine-virtual-monitor'
$log="$b\fix6-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $log -Append }
"=== FIX6 START $(Get-Date -Format o) ===" | Set-Content $log
$mt="$b\multimonitortool-x64\MultiMonitorTool.exe"
function Scan { & $mt /scomma "$b\_s6.csv" | Out-Null; Start-Sleep 1; Import-Csv "$b\_s6.csv" }
function Topo($r){ ($r | %{ "$($_.Name)[$($_.'Monitor Name')] act=$($_.Active) prim=$($_.Primary) disc=$($_.Disconnected)" }) -join ' | ' }

# keep the VDD pnp device ENABLED (Sunshine needs it present to activate on demand)
$vddDev = Get-PnpDevice -Class Display | ?{ $_.FriendlyName -like 'Virtual Display*' } | Select -First 1
L "VDD pnp status=$($vddDev.Status) (must stay OK/enabled)"
if ($vddDev.Status -ne 'OK') { try { $vddDev | Enable-PnpDevice -Confirm:$false; Start-Sleep 3; L 'VDD pnp re-enabled' } catch { L "ERR enable vdd: $_" } }

L ("BEFORE: " + (Topo (Scan)))

# --- baseline = internal/laptop ONLY  (SDC_APPLY 0x80 | SDC_TOPOLOGY_INTERNAL 0x01) ---
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class CCD { [DllImport("user32.dll")] public static extern int SetDisplayConfig(
  uint n1, IntPtr p1, uint n2, IntPtr p2, uint flags); }
"@
$rc=[CCD]::SetDisplayConfig(0,[IntPtr]::Zero,0,[IntPtr]::Zero,(0x80 -bor 0x01))
L "SetDisplayConfig(INTERNAL-ONLY) rc=$rc (0=success)"
Start-Sleep 4
$after = Scan
L ("AFTER: " + (Topo $after))

# fallback: if the VDD is still active, deactivate just it via MMT
$vddRow = $after | ?{ $_.'Monitor Name' -like '*VDD*' -or $_.'Monitor Name' -like '*MTT*' } | Select -First 1
if ($vddRow -and $vddRow.Active -eq 'Yes') {
  L "VDD still active after INTERNAL topology; MMT /disable $($vddRow.Name)"
  & $mt /disable $vddRow.Name ; Start-Sleep 3
  $after = Scan; L ("AFTER MMT disable: " + (Topo $after))
  $vddRow = $after | ?{ $_.'Monitor Name' -like '*VDD*' -or $_.'Monitor Name' -like '*MTT*' } | Select -First 1
}
$vddActive = ($vddRow -and $vddRow.Active -eq 'Yes')
$lapRow = $after | ?{ $_.Name -match '^\\\\\.\\DISPLAY' -and -not ($_.'Monitor Name' -match 'VDD|MTT') -and $_.Active -eq 'Yes' } | Select -First 1
L "idle state -> laptop active=$([bool]$lapRow) | VDD active=$vddActive (want: laptop yes, VDD no)"

# --- sunshine.conf: add revert-on-disconnect, keep the working keys ---
$conf='C:\Program Files\Sunshine\config\sunshine.conf'
Copy-Item $conf "$conf.bak-fix6-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
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
Set-Content -Path $conf -Value (@($kept | ?{ $_.Trim() -ne '' }) + $desired) -Encoding ASCII
L "sunshine.conf updated:"; Get-Content $conf | %{ L "  | $_" }

# restart + verify
try { Stop-Service SunshineService -Force -EA SilentlyContinue } catch {}
Start-Sleep 2
Get-Process sunshine,sunshinesvc -EA SilentlyContinue | %{ try{Stop-Process -Id $_.Id -Force}catch{} }
Start-Sleep 2
Start-Service SunshineService
$ok=$false
for($i=0;$i -lt 20;$i++){ Start-Sleep 2
  if((Get-Process sunshine -EA SilentlyContinue) -and (Get-NetTCPConnection -State Listen -EA SilentlyContinue | ? LocalPort -in 47984,47989,48010)){ $ok=$true; break } }
Start-Sleep 3
$crash=(Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=(Get-Date).AddMinutes(-2)} -EA SilentlyContinue | ? Message -match 'Sunshine'|Measure-Object).Count
L "listener=$(if($ok){'UP'}else{'DOWN'}) crashes2min=$crash"
Get-Content 'C:\Program Files\Sunshine\config\sunshine.log' | Select-String "config: '(dd_config_revert_on_disconnect|dd_configuration_option|output_name)'" | Select -Last 3 | %{ L ("  "+$_.Line.Substring($_.Line.IndexOf('config:'))) }
L ("RESULT=" + $(if($ok -and -not $vddActive -and $crash -eq 0){'OK - VDD now on-demand (idle=laptop only). Test: connect=VDD appears, quit=VDD gone ~3s'}else{'CHECK ABOVE'}))
"=== FIX6 END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
