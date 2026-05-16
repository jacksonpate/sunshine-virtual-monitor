# =====================================================================
#  Sunshine Virtual Monitor — one-shot deploy for a FRESH Windows PC.
#  Run ELEVATED from the repo:  powershell -ExecutionPolicy Bypass -File .\scripts\deploy-new-machine.ps1
#
#  Installs the signed VDD driver, drops vdd_settings.xml, then auto-derives
#  THIS machine's VDD device_id from sunshine.log and writes a correct
#  sunshine.conf (the device_id GUID is unique per machine).
#  Prereq: Sunshine already installed + SunshineService present.
# =====================================================================
$ErrorActionPreference = 'Stop'
function Say($m){ Write-Host ("[deploy] {0}" -f $m) }

# --- elevation check ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
  Write-Host "Must run elevated. Re-launching with UAC..." -ForegroundColor Yellow
  Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath
  return
}

$repo  = Split-Path $PSScriptRoot -Parent
$arch  = $env:PROCESSOR_ARCHITECTURE
$drvDir = if ($arch -eq 'ARM64') { "$repo\driver\SignedDrivers\ARM64\VDD" } else { "$repo\driver\SignedDrivers\x86\VDD" }
$inf    = "$drvDir\MttVDD.inf"
$devcon = "$repo\driver\Dependencies\devcon.exe"
Say "repo=$repo arch=$arch"
if (-not (Test-Path $inf)) { throw "driver inf not found: $inf" }

# --- locate Sunshine ---
$svc = Get-CimInstance Win32_Service -Filter "Name='SunshineService'" -ErrorAction SilentlyContinue
if (-not $svc) { throw "SunshineService not found — install Sunshine first." }
$sunRoot = Split-Path (Split-Path ($svc.PathName.Trim('"')) -Parent) -Parent   # ...\Sunshine\tools\sunshinesvc.exe -> ...\Sunshine
$conf    = Join-Path $sunRoot 'config\sunshine.conf'
$slog    = Join-Path $sunRoot 'config\sunshine.log'
Say "sunshine root=$sunRoot"

# --- 1. install signed VDD driver + create Root\MttVDD device ---
Say "installing driver package..."
& pnputil /add-driver "$inf" /install | Out-Null
if ($arch -ne 'ARM64') {
  Say "creating Root\MttVDD device via devcon..."
  & $devcon install "$inf" "Root\MttVDD" | Out-Null
} else {
  Say "ARM64: devcon not bundled — if the device isn't auto-created, add legacy hardware 'Root\MttVDD' in Device Manager."
}

# --- 2. driver settings file ---
New-Item -ItemType Directory -Force -Path 'C:\VirtualDisplayDriver' | Out-Null
Copy-Item "$repo\config\vdd_settings.xml" 'C:\VirtualDisplayDriver\vdd_settings.xml' -Force
Say "vdd_settings.xml -> C:\VirtualDisplayDriver\"

# --- 3. ensure VDD pnp device enabled ---
Start-Sleep 3
$vdd = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object {
  $_.FriendlyName -like 'Virtual Display*' -or $_.FriendlyName -like '*MTT*' } | Select-Object -First 1
if ($vdd -and $vdd.Status -ne 'OK') { $vdd | Enable-PnpDevice -Confirm:$false }
Say ("VDD device: '{0}' status={1}" -f $vdd.FriendlyName, (Get-PnpDevice -InstanceId $vdd.InstanceId).Status)

function Restart-Sun {
  Stop-Service SunshineService -Force -ErrorAction SilentlyContinue
  Start-Sleep 2
  Get-Process sunshine,sunshinesvc -ErrorAction SilentlyContinue | ForEach-Object { try{Stop-Process -Id $_.Id -Force}catch{} }
  Start-Sleep 2
  Start-Service SunshineService
  for($i=0;$i -lt 25;$i++){ Start-Sleep 2
    if((Get-Process sunshine -ErrorAction SilentlyContinue) -and (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in 47984,47989,48010)){ return $true } }
  return $false
}

# --- 4. restart Sunshine so it enumerates + logs device_ids ---
Say "restarting Sunshine to enumerate displays..."
[void](Restart-Sun); Start-Sleep 4

# --- 5. derive THIS machine's VDD device_id from sunshine.log ---
$raw = Get-Content $slog -Raw
$vddId = $null
foreach($m in [regex]::Matches($raw,'"device_id":\s*"(\{[0-9a-fA-F-]+\})"')){
  $win = $raw.Substring($m.Index, [Math]::Min(400, $raw.Length - $m.Index))
  if ($win -match 'VDD by MTT|"manufacturer_id":\s*"MTT"|Virtual Display Driver') { $vddId = $m.Groups[1].Value; break }
}
if (-not $vddId) { throw "Could not find the VDD device_id in $slog. Connect once from Moonlight, then re-run, or set output_name manually from the log." }
Say "VDD device_id (this machine) = $vddId"

# --- 6. write sunshine.conf from the repo template with the correct GUID ---
if (Test-Path $conf) { Copy-Item $conf "$conf.bak-predeploy-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force }
$lines = Get-Content "$repo\config\sunshine.conf" | ForEach-Object {
  if ($_ -match '^\s*output_name\s*=') { "output_name = $vddId" } else { $_ }
}
if (-not ($lines -match '^\s*output_name\s*=')) { $lines = @("output_name = $vddId") + $lines }
Set-Content -Path $conf -Value $lines -Encoding ASCII
Say "wrote $conf"

# --- 7. restart + verify ---
$up = Restart-Sun
Start-Sleep 3
$parsed = (Get-Content $slog | Select-String "config: 'output_name'" | Select-Object -Last 1).Line
Say ("Sunshine listener = {0}" -f $(if($up){'UP'}else{'DOWN — check Sunshine'}))
Say ("parsed: {0}" -f ($parsed -replace '^.*config:', 'config:'))
Write-Host ""
Write-Host "DONE. Connect from Moonlight — you should get the VDD as a second monitor." -ForegroundColor Green
Write-Host "If color looks washed: HDR is disabled by design on dual; see README." -ForegroundColor DarkGray
