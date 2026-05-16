# ELEVATED fix #5: use Sunshine's NATIVE display-device handling.
# Correct output_name = the VDD's stable device_id GUID (NOT \\.\DISPLAYn).
# dd_* options make Sunshine itself drive the VDD (active during stream, laptop stays,
# auto-match iPad/iPhone res/refresh/HDR, auto-revert on disconnect). No scripts.
$ErrorActionPreference='Continue'
$b='C:\jacks\AI\sunshine-virtual-monitor'
$log="$b\fix5-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $log -Append }
"=== FIX5 START $(Get-Date -Format o) ===" | Set-Content $log

$conf='C:\Program Files\Sunshine\config\sunshine.conf'
Copy-Item $conf "$conf.bak-fix5-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force

$VDD_ID = '{9acddf6d-43cc-576e-9aff-0c5fc80b4cc8}'   # VDD by MTT (stable device_id)
$desired = @(
  "output_name = $VDD_ID"
  'dd_configuration_option = ensure_active'
  'dd_resolution_option = auto'
  'dd_refresh_rate_option = auto'
  'dd_hdr_option = auto'
  'dd_config_revert_delay = 3000'
)
# strip any prior copies of these keys + the dead global_prep_cmd, then append clean block
$keys = 'output_name','dd_configuration_option','dd_resolution_option','dd_refresh_rate_option','dd_hdr_option','dd_config_revert_delay','global_prep_cmd'
$kept = Get-Content $conf | Where-Object { $line=$_; -not ($keys | Where-Object { $line -match ("^\s*" + [regex]::Escape($_) + "\s*=") }) }
$final = (@($kept | Where-Object { $_.Trim() -ne '' }) + $desired)
Set-Content -Path $conf -Value $final -Encoding ASCII
L "sunshine.conf written:"
Get-Content $conf | ForEach-Object { L "  | $_" }

# restart + verify Sunshine parses the new keys
try { Stop-Service SunshineService -Force -EA SilentlyContinue } catch {}
Start-Sleep 2
Get-Process sunshine,sunshinesvc -EA SilentlyContinue | ForEach-Object { try{Stop-Process -Id $_.Id -Force}catch{} }
Start-Sleep 2
Start-Service SunshineService
$ok=$false
for($i=0;$i -lt 20;$i++){ Start-Sleep 2
  if((Get-Process sunshine -EA SilentlyContinue) -and (Get-NetTCPConnection -State Listen -EA SilentlyContinue | ? LocalPort -in 47984,47989,48010)){ $ok=$true; break } }
Start-Sleep 3
$slog='C:\Program Files\Sunshine\config\sunshine.log'
L "listener=$(if($ok){'UP'}else{'DOWN'})"
L "Sunshine parsed config (startup):"
Get-Content $slog | Select-String -Pattern "config: '(output_name|dd_configuration_option|dd_resolution_option|dd_refresh_rate_option|dd_hdr_option|dd_config_revert_delay)'" | Select-Object -Last 6 | ForEach-Object { L ("  " + $_.Line.Substring($_.Line.IndexOf('config:'))) }
$crash=(Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=(Get-Date).AddMinutes(-2)} -EA SilentlyContinue | ? Message -match 'Sunshine'|Measure-Object).Count
L "crashes2min=$crash"
L ("RESULT=" + $(if($ok -and $crash -eq 0){'READY - reconnect Moonlight (VDD should now be the streamed screen, auto-sized to your device)'}else{'PROBLEM - check above'}))
"=== FIX5 END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
