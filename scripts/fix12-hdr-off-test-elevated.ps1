# ELEVATED diagnostic: dd_hdr_option enabled -> disabled (pure SDR dual). Isolates
# whether the "faded out" look is HDR-mapping or a colorspace/range issue.
$ErrorActionPreference='Continue'
$b='C:\jacks\AI\sunshine-virtual-monitor'; $log="$b\fix12-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $log -Append }
"=== FIX12 START $(Get-Date -Format o) ===" | Set-Content $log
$conf='C:\Program Files\Sunshine\config\sunshine.conf'
Copy-Item $conf "$conf.bak-fix12-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
$lines = Get-Content $conf | ForEach-Object { if($_ -match '^\s*dd_hdr_option\s*='){ 'dd_hdr_option = disabled' } else { $_ } }
Set-Content $conf -Value $lines -Encoding ASCII
L "conf now:"; Get-Content $conf | %{ L "  | $_" }
Stop-Service SunshineService -Force -EA SilentlyContinue; Start-Sleep 2
Get-Process sunshine,sunshinesvc -EA SilentlyContinue | %{ try{Stop-Process -Id $_.Id -Force}catch{} }
Start-Sleep 2; Start-Service SunshineService
$up=$false
for($i=0;$i -lt 20;$i++){ Start-Sleep 2; if((Get-Process sunshine -EA SilentlyContinue) -and (Get-NetTCPConnection -State Listen -EA SilentlyContinue|? LocalPort -in 47984,47989,48010)){ $up=$true; break } }
Start-Sleep 3
Get-Content 'C:\Program Files\Sunshine\config\sunshine.log' | Select-String "config: 'dd_hdr_option'" | Select -Last 1 | %{ L ("  "+$_.Line.Substring($_.Line.IndexOf('config:'))) }
$crash=(Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=(Get-Date).AddMinutes(-2)} -EA SilentlyContinue|? Message -match 'Sunshine'|Measure-Object).Count
L "listener=$(if($up){'UP'}else{'DOWN'}) crashes2min=$crash"
L "RESULT=$(if($up -and $crash -eq 0){'READY - reconnect. Is the faded look GONE (->was HDR) or STILL there (->colorspace/range)?'}else{'PROBLEM'})"
"=== FIX12 END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
