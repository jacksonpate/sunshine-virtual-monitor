# Sunshine-Virtual-Monitor one-time ELEVATED installer.
# Runs every admin step unattended. Logs to install-result.txt for non-admin verification.
$ErrorActionPreference = 'Continue'
$base = 'C:\jacks\AI\sunshine-virtual-monitor'
$log  = "$base\install-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss), $m | Tee-Object -FilePath $log -Append }
"=== INSTALL START $(Get-Date -Format o) ===" | Set-Content $log

# admin sanity
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
L "elevated=$admin"
if (-not $admin) { L "NOT ELEVATED - abort"; exit 1 }

# 1. WindowsDisplayManager module (AllUsers so the SYSTEM-run Sunshine prep can import it)
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
  }
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
  if (-not (Get-Module -ListAvailable WindowsDisplayManager)) {
    Install-Module -Name WindowsDisplayManager -Scope AllUsers -Force -AllowClobber
  }
  $wdm = Get-Module -ListAvailable WindowsDisplayManager | Select-Object -First 1
  L "WindowsDisplayManager: $($wdm.Version) @ $($wdm.ModuleBase)"
} catch { L "ERR module: $_" }

# 2. Install signed VDD driver + create Root\MttVDD device node
$inf    = "$base\SignedDrivers\x86\VDD\MttVDD.inf"
$devcon = "$base\Dependencies\devcon.exe"
try {
  $p = & pnputil /add-driver "$inf" /install 2>&1; L "pnputil add-driver: $($p -join ' | ')"
} catch { L "ERR add-driver: $_" }
try {
  $d = & $devcon install "$inf" "Root\MttVDD" 2>&1; L "devcon install: $($d -join ' | ')"
} catch { L "ERR devcon: $_" }

# 3. Driver settings file at the path setup_sunvdm.ps1 reads
try {
  New-Item -ItemType Directory -Force -Path 'C:\VirtualDisplayDriver' | Out-Null
  Copy-Item "$base\Dependencies\vdd_settings.xml" 'C:\VirtualDisplayDriver\vdd_settings.xml' -Force
  L "vdd_settings.xml -> C:\VirtualDisplayDriver\ ($(Test-Path 'C:\VirtualDisplayDriver\vdd_settings.xml'))"
} catch { L "ERR settings: $_" }

# 4. Find the VDD device, then DISABLE it (dormant until a Moonlight stream starts)
Start-Sleep 3
$vdd = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object {
  $_.FriendlyName -like '*idd*' -or $_.FriendlyName -like '*mtt*' -or $_.FriendlyName -like 'Virtual Display*'
} | Select-Object -First 1
if ($vdd) {
  L "VDD device: '$($vdd.FriendlyName)' status=$($vdd.Status) instance=$($vdd.InstanceId)"
  try { $vdd | Disable-PnpDevice -Confirm:$false -ErrorAction Stop; L "VDD disabled (dormant)" }
  catch { L "ERR disable: $_" }
} else { L "ERR: VDD device NOT found after install" }

# 5. Wire Sunshine global_prep_cmd (do/undo) -> setup/teardown scripts, elevated
$conf = 'C:\Program Files\Sunshine\config\sunshine.conf'
$do   = "cmd /C powershell.exe -executionpolicy bypass -windowstyle hidden -file \`"$base\setup_sunvdm.ps1\`" > \`"$base\sunvdm.log\`" 2>&1"
$undo = "cmd /C powershell.exe -executionpolicy bypass -windowstyle hidden -file \`"$base\teardown_sunvdm.ps1\`" >> \`"$base\sunvdm.log\`" 2>&1"
$prep = 'global_prep_cmd = [{"do":"' + $do + '","undo":"' + $undo + '","elevated":"true"}]'
try {
  $cur = if (Test-Path $conf) { Get-Content $conf -Raw } else { '' }
  $cur = ($cur -split "`r?`n" | Where-Object { $_ -notmatch '^\s*global_prep_cmd\s*=' }) -join "`r`n"
  $new = ($cur.TrimEnd() + "`r`n" + $prep + "`r`n").TrimStart("`r","`n")
  Set-Content -Path $conf -Value $new -Encoding ASCII
  L "sunshine.conf global_prep_cmd written"
} catch { L "ERR conf: $_" }

# 6. Restart Sunshine so it reloads config
try { Restart-Service SunshineService -Force; Start-Sleep 2; L "SunshineService: $((Get-Service SunshineService).Status)" }
catch { L "ERR svc restart: $_" }

"=== INSTALL END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
