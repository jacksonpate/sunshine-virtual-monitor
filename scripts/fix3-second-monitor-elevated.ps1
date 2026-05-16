# ELEVATED fix #3: real "second monitor" topology.
#   laptop panel = active + PRIMARY (main screen)
#   VDD          = active + extended secondary
#   Sunshine output_name -> the VDD's \\.\DISPLAYn (stream ONLY the VDD)
$ErrorActionPreference='Continue'
$b='C:\jacks\AI\sunshine-virtual-monitor'
$log="$b\fix3-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $log -Append }
"=== FIX3 START $(Get-Date -Format o) ===" | Set-Content $log
L ("elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))
$mt="$b\multimonitortool-x64\MultiMonitorTool.exe"
function Scan { & $mt /scomma "$b\_s.csv" | Out-Null; Start-Sleep 1; Import-Csv "$b\_s.csv" }

# ensure VDD pnp device enabled
$vddDev = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -like 'Virtual Display*' } | Select-Object -First 1
if ($vddDev.Status -ne 'OK') { try { $vddDev | Enable-PnpDevice -Confirm:$false; Start-Sleep 3; L "VDD pnp enabled" } catch { L "ERR enable vdd: $_" } }

$before = Scan
L ("BEFORE: " + (($before | ForEach-Object { "$($_.Name)[$($_.'Monitor Name')|$($_.'Short Monitor ID')] act=$($_.Active) prim=$($_.Primary)" }) -join ' | '))

# VDD = the row whose monitor name/id is VDD/MTT. LAPTOP = the other \\.\DISPLAY row
# (when the panel is disabled MMT reports it with blank name/id, so resolve by elimination).
function FindVdd($rows){ $rows | Where-Object { $_.'Monitor Name' -like '*VDD*' -or $_.'Monitor Name' -like '*MTT*' -or $_.'Short Monitor ID' -like 'MTT*' } | Select-Object -First 1 }
$vdd = FindVdd $before
$lap = $before | Where-Object { $_.Name -match '^\\\\\.\\DISPLAY' -and $_.Name -ne $vdd.Name } | Select-Object -First 1
L "resolved lap=$($lap.Name) vdd=$($vdd.Name)"
if (-not $lap -or -not $vdd) { L "ERR could not resolve both displays; ABORT"; "=== FIX3 END ABORT ===" | Tee-Object $log -Append; exit 1 }

# enable laptop panel + keep VDD; make laptop PRIMARY (extends VDD automatically)
& $mt /enable $lap.Name ; Start-Sleep 3
& $mt /enable $vdd.Name ; Start-Sleep 2
& $mt /SetPrimary $lap.Name ; Start-Sleep 3

# re-resolve from the settled topology (numbers can shift when a display is added)
$after = Scan
$vddA = FindVdd $after
$lapA = $after | Where-Object { $_.Name -match '^\\\\\.\\DISPLAY' -and $_.Name -ne $vddA.Name } | Select-Object -First 1
if ($vddA.Primary -eq 'Yes' -and $lapA) { & $mt /SetPrimary $lapA.Name; Start-Sleep 3; $after = Scan; $vddA = FindVdd $after; $lapA = $after | Where-Object { $_.Name -match '^\\\\\.\\DISPLAY' -and $_.Name -ne $vddA.Name } | Select-Object -First 1 }
L ("AFTER: " + (($after | ForEach-Object { "$($_.Name)[$($_.'Monitor Name')] act=$($_.Active) prim=$($_.Primary) res=$($_.Resolution)" }) -join ' | '))
if ($lapA.Active -ne 'Yes') { L "WARN laptop panel did NOT reactivate (still act=$($lapA.Active))" }

# pin Sunshine to the VDD output (plain string value in sunshine.conf, NOT json -> literal backslashes)
$conf='C:\Program Files\Sunshine\config\sunshine.conf'
Copy-Item $conf "$conf.bak-fix3-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
$vddOut = $vddA.Name   # \\.\DISPLAYn from the SETTLED topology (dxgi-info + MMT share this namespace)
$lines = @(Get-Content $conf | Where-Object { $_ -notmatch '^\s*output_name\s*=' -and $_ -notmatch '^\s*global_prep_cmd\s*=' })
$lines = @($lines) + ("output_name = " + $vddOut)
Set-Content -Path $conf -Value $lines -Encoding ASCII
L "sunshine.conf output_name = $vddOut"

# restart Sunshine, verify it actually sees that output + listener up
try { Stop-Service SunshineService -Force -EA SilentlyContinue } catch {}
Start-Sleep 2
Get-Process sunshine,sunshinesvc -EA SilentlyContinue | ForEach-Object { try{Stop-Process -Id $_.Id -Force}catch{} }
Start-Sleep 2
Start-Service SunshineService
L "Sunshine restarted"
$ok=$false
for($i=0;$i -lt 20;$i++){ Start-Sleep 2
  $p=Get-Process sunshine -EA SilentlyContinue
  $port=Get-NetTCPConnection -State Listen -EA SilentlyContinue | Where-Object LocalPort -in 47984,47989,48010
  if($p -and $port){ $ok=$true; break } }
$dxgi = & 'C:\Program Files\Sunshine\tools\dxgi-info.exe' 2>&1
$seesVdd = ($dxgi | Select-String ([regex]::Escape($vddOut))).Count -gt 0
$port=Get-NetTCPConnection -State Listen -EA SilentlyContinue | Where-Object LocalPort -in 47984,47989,48010
L ("listener=" + $(if($ok){'UP'}else{'DOWN'}) + " ports=" + (($port.LocalPort|sort -u) -join ',') + " dxgi_sees_$vddOut=$seesVdd")
$cr=Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=(Get-Date).AddMinutes(-2)} -EA SilentlyContinue | ? Message -match 'Sunshine'
L ("Sunshine crashes last 2min=" + (($cr|Measure-Object).Count))
L ("RESULT: laptop=" + $lapA.Name + " active=" + $lapA.Active + " primary=" + $lapA.Primary + " | vdd=" + $vddA.Name + " active=" + $vddA.Active + " primary=" + $vddA.Primary + " -> stream target " + $vddOut)
"=== FIX3 END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
