# roam-lib.ps1  (Pate-PC / pate-desktop)
# Shared transition primitives for the all-monitors <-> ipad-only roam watcher.
#
# Adapted from the upstream (Zephyrus / single-panel laptop) roam-lib. This rig
# has THREE physical monitors + the MTT VDD, so every transition acts on the
# explicit Short Monitor IDs that privacy-on/off already prove work here. That
# also sidesteps runbook FOOTGUN #3 (\\.\DISPLAYn renumbers every topology
# change; never key off it).
#
# States:
#   ALL   (iPad bottom-LEFT  3s) - all 3 physical monitors ON, Acer primary,
#                                  VDD stays an extended display so the iPad
#                                  keeps streaming.  "all of my monitors".
#   AWAY  (iPad bottom-RIGHT 3s) - all physical OFF, VDD = the whole desktop.
#                                  "just the iPad display" (== upstream clone).

$script:ROAM = 'C:\jacks\AI\sunshine-virtual-monitor\roam'
$script:MMT  = 'C:\Users\jacks\Downloads\tools\MultiMonitorTool.exe'
$script:RLOG = "$script:ROAM\roam.log"

# Pate-PC topology (moonlight-setup README "Critical IDs" + live MMT scan 2026-05-16)
$script:VDD_ID     = 'MTT1337'                          # "VDD by MTT" - Sunshine output_name {5eb52002-659f-5729-bdd8-9cdc4efd1bf5}
$script:PHYS_IDS   = @('ACR0E02','SAM7016','SAM727B')   # Acer / Samsung 8K / Samsung Odyssey
$script:PRIMARY_ID = 'ACR0E02'                          # desk primary when all monitors are on

function RLog($m){ try { "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $m | Out-File $script:RLOG -Append -Encoding utf8 } catch {} }

function Get-Mons {
  $csv = "$script:ROAM\_scan.csv"
  & $script:MMT /scomma $csv | Out-Null
  Start-Sleep -Milliseconds 400
  if (Test-Path $csv) { Import-Csv $csv } else { @() }
}
function Row-ById($m,$id){ $m | Where-Object { $_.'Short Monitor ID' -eq $id } | Select-Object -First 1 }
function Vdd-Row ($m){ Row-ById $m $script:VDD_ID }

# Is a Moonlight client actually connected right now? (gate before going AWAY).
# Scan the WHOLE log - Sunshine writes ~200 lines per connect, a fixed tail
# misses the CLIENT CONNECTED line. Last CONNECTED/DISCONNECTED match = truth.
function Session-Live {
  try {
    $log  = 'C:\Program Files\Sunshine\config\sunshine.log'
    $hits = Select-String -Path $log -Pattern 'CLIENT CONNECTED','CLIENT DISCONNECTED' -ErrorAction SilentlyContinue
    $last = $hits | Select-Object -Last 1
    return [bool]($last -and $last.Line -match 'CLIENT CONNECTED')
  } catch { return $false }
}

function Vdd-Active   { $v = Vdd-Row (Get-Mons); return ($v -and $v.Active -eq 'Yes') }
function AnyPhys-Active {
  $m = Get-Mons
  foreach ($id in $script:PHYS_IDS) { $r = Row-ById $m $id; if ($r -and $r.Active -eq 'Yes') { return $true } }
  return $false
}
function AllPhys-Active {
  $m = Get-Mons
  foreach ($id in $script:PHYS_IDS) { $r = Row-ById $m $id; if (-not ($r -and $r.Active -eq 'Yes')) { return $false } }
  return $true
}

# Find the *real* running watcher process(es). The actual cmdline is
#   powershell.exe ... -File "<...>\roam\roam-watcher.ps1"
# so require -File + the roam\roam-watcher.ps1 path and exclude the current
# process. (A bare 'roam-watcher.ps1' substring match - the upstream predicate
# - also matches diagnostics/one-liners that merely mention the filename.)
function Get-WatcherProcs {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '-File\s+"?[^"]*roam[\\/]roam-watcher\.ps1' }
}

Add-Type @"
using System; using System.Runtime.InteropServices;
public static class RoamCCD { [DllImport("user32.dll")] public static extern int SetDisplayConfig(uint a,IntPtr b,uint c,IntPtr d,uint f); }
"@ -ErrorAction SilentlyContinue

# ---- AWAY (iPad bottom-RIGHT): all physical OFF, VDD = sole desktop. ----
# Same effect as moonlight-setup\scripts\privacy-on.ps1, plus the upstream
# clone's safety gates + verify + auto-revert.
function Go-Away {
  if (-not (Session-Live)) { RLog 'AWAY refused: no live Moonlight session'; return $false }
  if (-not (Vdd-Active))   { RLog 'AWAY refused: VDD not active';            return $false }
  RLog "AWAY: /SetPrimary $script:VDD_ID ; /disable $($script:PHYS_IDS -join ' ')"
  & $script:MMT /SetPrimary $script:VDD_ID | Out-Null;       Start-Sleep -Milliseconds 700
  & $script:MMT /disable    $script:PHYS_IDS | Out-Null;     Start-Sleep -Milliseconds 900
  if ((Vdd-Active) -and -not (AnyPhys-Active)) { RLog 'AWAY ok'; return $true }
  RLog 'AWAY verify failed -> reverting to ALL'; Go-All | Out-Null; return $false
}

# ---- ALL (iPad bottom-LEFT): all 3 physical ON + Acer primary, VDD stays ----
# an extended display so the stream keeps running. Same effect as
# moonlight-setup\scripts\privacy-off.ps1, plus a CCD extend rebuild so the
# VDD is re-attached as an extended monitor (Sunshine still captures it).
function Go-All {
  RLog "ALL: /enable $($script:PHYS_IDS -join ' ') ; extend ; /SetPrimary $script:PRIMARY_ID"
  & $script:MMT /enable $script:PHYS_IDS | Out-Null;          Start-Sleep -Milliseconds 900
  # SDC_APPLY|SDC_TOPOLOGY_EXTEND = 0x84 - rebuild the extended desktop across
  # ALL connected displays (re-attaches the VDD as an extended monitor).
  [void][RoamCCD]::SetDisplayConfig(0,[IntPtr]::Zero,0,[IntPtr]::Zero,(0x80 -bor 0x04)); Start-Sleep -Milliseconds 1200
  & $script:MMT /enable $script:PHYS_IDS | Out-Null;          Start-Sleep -Milliseconds 500   # re-assert (extend can drop one)
  & $script:MMT /SetPrimary $script:PRIMARY_ID | Out-Null;    Start-Sleep -Milliseconds 500
  $m = Get-Mons; $v = Vdd-Row $m
  $allOn = $true
  foreach ($id in $script:PHYS_IDS) { $r = Row-ById $m $id; if (-not ($r -and $r.Active -eq 'Yes')) { $allOn = $false } }
  RLog ("ALL done: physAllOn={0} VDD={1}" -f $allOn, $(if ($v) { $v.Active } else { '<none>' }))
  return $true
}
