# ELEVATED fix #4: force-rebuild EXTENDED desktop across ALL connected displays
# (internal panel was left detached; MMT /enable can't recover that -> use CCD API).
# Then: laptop = primary, VDD = extended secondary, Sunshine output_name -> VDD.
$ErrorActionPreference='Continue'
$b='C:\jacks\AI\sunshine-virtual-monitor'
$log="$b\fix4-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $log -Append }
"=== FIX4 START $(Get-Date -Format o) ===" | Set-Content $log
$mt="$b\multimonitortool-x64\MultiMonitorTool.exe"
function Scan { & $mt /scomma "$b\_s4.csv" | Out-Null; Start-Sleep 1; Import-Csv "$b\_s4.csv" }
function FindVdd($r){ $r | ?{ $_.'Monitor Name' -like '*VDD*' -or $_.'Monitor Name' -like '*MTT*' -or $_.'Short Monitor ID' -like 'MTT*' } | Select -First 1 }
function Topo($r){ ($r | %{ "$($_.Name)[$($_.'Monitor Name')] act=$($_.Active) prim=$($_.Primary) disc=$($_.Disconnected)" }) -join ' | ' }

# make sure VDD pnp device is enabled
$vddDev = Get-PnpDevice -Class Display | ?{ $_.FriendlyName -like 'Virtual Display*' } | Select -First 1
if ($vddDev.Status -ne 'OK') { try { $vddDev | Enable-PnpDevice -Confirm:$false; Start-Sleep 4; L 'VDD pnp enabled' } catch { L "ERR enable vdd: $_" } }

L ("BEFORE: " + (Topo (Scan)))

# --- CCD: SetDisplayConfig(SDC_APPLY | SDC_TOPOLOGY_EXTEND) = rebuild extended desktop ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CCD {
  [DllImport("user32.dll")] public static extern int SetDisplayConfig(
    uint numPathArrayElements, IntPtr pathArray,
    uint numModeInfoArrayElements, IntPtr modeInfoArray, uint flags);
}
"@
$SDC_APPLY=0x00000080; $SDC_TOPOLOGY_EXTEND=0x00000004
$rc = [CCD]::SetDisplayConfig(0,[IntPtr]::Zero,0,[IntPtr]::Zero,($SDC_APPLY -bor $SDC_TOPOLOGY_EXTEND))
L "SetDisplayConfig(EXTEND) rc=$rc (0=success)"
Start-Sleep 4

$after = Scan
L ("AFTER EXTEND: " + (Topo $after))
$active = @($after | ?{ $_.Active -eq 'Yes' })
if ($active.Count -lt 2) {
  # fallback: DisplaySwitch /extend in the interactive session
  L "still <2 active; trying DisplaySwitch /extend"
  Start-Process "$env:WINDIR\System32\DisplaySwitch.exe" -ArgumentList '/extend' -Wait
  Start-Sleep 4; $after = Scan; L ("AFTER DisplaySwitch: " + (Topo $after))
  $active = @($after | ?{ $_.Active -eq 'Yes' })
}

$vddA = FindVdd $after
$lapA = $after | ?{ $_.Name -match '^\\\\\.\\DISPLAY' -and $_.Name -ne $vddA.Name } | Select -First 1

# laptop = primary main screen
if ($lapA -and $lapA.Active -eq 'Yes') {
  & $mt /SetPrimary $lapA.Name; Start-Sleep 3
  $after = Scan; $vddA = FindVdd $after
  $lapA = $after | ?{ $_.Name -match '^\\\\\.\\DISPLAY' -and $_.Name -ne $vddA.Name } | Select -First 1
  L ("AFTER SetPrimary(laptop): " + (Topo $after))
}

$lapOk = ($lapA -and $lapA.Active -eq 'Yes')
$vddOk = ($vddA -and $vddA.Active -eq 'Yes')
L "laptop active=$($lapA.Active) primary=$($lapA.Primary) | vdd active=$($vddA.Active) primary=$($vddA.Primary)"

# pin Sunshine to the VDD (plain string in sunshine.conf -> literal backslashes, NOT json)
$conf='C:\Program Files\Sunshine\config\sunshine.conf'
Copy-Item $conf "$conf.bak-fix4-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
$vddOut = $vddA.Name
$lines = @(Get-Content $conf | ?{ $_ -notmatch '^\s*output_name\s*=' -and $_ -notmatch '^\s*global_prep_cmd\s*=' })
$lines = @($lines) + ("output_name = " + $vddOut)
Set-Content -Path $conf -Value $lines -Encoding ASCII
L "sunshine.conf output_name = $vddOut"

# restart + verify
try { Stop-Service SunshineService -Force -EA SilentlyContinue } catch {}
Start-Sleep 2
Get-Process sunshine,sunshinesvc -EA SilentlyContinue | %{ try{Stop-Process -Id $_.Id -Force}catch{} }
Start-Sleep 2
Start-Service SunshineService
$ok=$false
for($i=0;$i -lt 20;$i++){ Start-Sleep 2
  if((Get-Process sunshine -EA SilentlyContinue) -and (Get-NetTCPConnection -State Listen -EA SilentlyContinue | ? LocalPort -in 47984,47989,48010)){ $ok=$true; break } }
$dxgi = & 'C:\Program Files\Sunshine\tools\dxgi-info.exe' 2>&1
$seesVdd = ($dxgi | Select-String ([regex]::Escape($vddOut))).Count -gt 0
L ("listener=" + $(if($ok){'UP'}else{'DOWN'}) + " dxgi_sees_$vddOut=$seesVdd crashes2min=" + ((Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=(Get-Date).AddMinutes(-2)} -EA SilentlyContinue | ? Message -match 'Sunshine'|Measure-Object).Count))
L ("RESULT: " + $(if($lapOk -and $vddOk){'OK - dual extended (laptop main + VDD streamed)'}elseif($vddOk){'PARTIAL - VDD ok but laptop panel still down'}else{'FAIL'}))
"=== FIX4 END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
