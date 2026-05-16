# ELEVATED: enable real HDR in the VDD driver EDID so HDR HOLDS (root cause of
# "HDR works a second then drops to SDR/yellow"). One change: HDRPlus false->true,
# then reload the VDD device so the new HDR EDID takes effect.
$ErrorActionPreference='Continue'
$b='C:\jacks\AI\sunshine-virtual-monitor'; $log="$b\fix11-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $log -Append }
"=== FIX11 START $(Get-Date -Format o) ===" | Set-Content $log
$xml='C:\VirtualDisplayDriver\vdd_settings.xml'
Copy-Item $xml "$b\vdd_settings.bak-$(Get-Date -Format yyyyMMdd-HHmmss).xml" -Force

$raw = Get-Content $xml -Raw
$before = ([regex]::Match($raw,'<HDRPlus>.*?</HDRPlus>').Value) + ' / ' + ([regex]::Match($raw,'<SDR10bit>.*?</SDR10bit>').Value)
L "before: $before"
# HDRPlus=true ; SDR10bit MUST stay false (driver: SDR10bit conflicts with HDRPlus)
$raw = $raw -replace '<HDRPlus>\s*false\s*</HDRPlus>','<HDRPlus>true</HDRPlus>'
$raw = $raw -replace '<SDR10bit>\s*true\s*</SDR10bit>','<SDR10bit>false</SDR10bit>'
Set-Content -Path $xml -Value $raw -Encoding UTF8
$after = ([regex]::Match((Get-Content $xml -Raw),'<HDRPlus>.*?</HDRPlus>').Value) + ' / ' + ([regex]::Match((Get-Content $xml -Raw),'<SDR10bit>.*?</SDR10bit>').Value)
L "after:  $after"

# reload the VDD so it re-reads vdd_settings.xml and re-publishes the EDID (now HDR)
$vdd = Get-PnpDevice -Class Display | ?{ $_.FriendlyName -like 'Virtual Display*' } | Select -First 1
L "VDD '$($vdd.FriendlyName)' status=$($vdd.Status) -> disable/enable to reload EDID"
try { $vdd | Disable-PnpDevice -Confirm:$false -EA Stop; Start-Sleep 3 } catch { L "disable: $_" }
try { $vdd | Enable-PnpDevice  -Confirm:$false -EA Stop; Start-Sleep 4 } catch { L "enable: $_" }
$vdd2 = Get-PnpDevice -InstanceId $vdd.InstanceId
L "VDD status now=$($vdd2.Status)"

# bounce Sunshine so a fresh session re-detects the now-HDR-capable VDD
Stop-Service SunshineService -Force -EA SilentlyContinue; Start-Sleep 2
Get-Process sunshine,sunshinesvc -EA SilentlyContinue | %{ try{Stop-Process -Id $_.Id -Force}catch{} }
Start-Sleep 2; Start-Service SunshineService
$up=$false
for($i=0;$i -lt 20;$i++){ Start-Sleep 2; if((Get-Process sunshine -EA SilentlyContinue) -and (Get-NetTCPConnection -State Listen -EA SilentlyContinue|? LocalPort -in 47984,47989,48010)){ $up=$true; break } }
$crash=(Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=(Get-Date).AddMinutes(-2)} -EA SilentlyContinue|? Message -match 'Sunshine'|Measure-Object).Count
L "Sunshine listener=$(if($up){'UP'}else{'DOWN'}) crashes2min=$crash"
L "RESULT=$(if($up -and $vdd2.Status -eq 'OK' -and $crash -eq 0){'READY - reconnect from iPad. HDR should now HOLD (deep/colorful, no drop to yellow).'}else{'CHECK ABOVE'})"
"=== FIX11 END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
