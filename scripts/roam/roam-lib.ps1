# roam-lib.ps1 — shared transition primitives (proven CCD + MMT logic from fix4/fix7).
# Dot-sourced by the watcher. Resolves displays at runtime (no hardcoded \\.\DISPLAYn).
$script:ROAM = 'C:\jacks\AI\sunshine-virtual-monitor'
$script:MMT  = "$ROAM\multimonitortool-x64\MultiMonitorTool.exe"
$script:RLOG = "$ROAM\roam\roam.log"

function RLog($m){ try { "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $m | Out-File $script:RLOG -Append -Encoding utf8 } catch {} }

function Get-Mons {
  $csv = "$ROAM\roam\_scan.csv"
  & $script:MMT /scomma $csv | Out-Null
  Start-Sleep -Milliseconds 400
  Import-Csv $csv
}
function Get-Vdd ($m){ $m | Where-Object { $_.'Monitor Name' -match 'VDD|MTT' -or $_.'Short Monitor ID' -match 'MTT' } | Select-Object -First 1 }
function Get-Phys($m,$vdd){ $m | Where-Object { $_.Name -match '^\\\\\.\\DISPLAY' -and $_.Name -ne $vdd.Name } | Select-Object -First 1 }

# Is a Moonlight client actually connected right now? (failsafe gate before going AWAY)
function Session-Live {
  # Scan the WHOLE log (not a fixed tail — Sunshine writes ~200 lines per connect,
  # which pushed the CLIENT CONNECTED line out of a tail window). The last
  # CONNECTED/DISCONNECTED match in the file is the truth.
  try {
    $log = 'C:\Program Files\Sunshine\config\sunshine.log'
    $hits = Select-String -Path $log -Pattern 'CLIENT CONNECTED','CLIENT DISCONNECTED' -ErrorAction SilentlyContinue
    $last = $hits | Select-Object -Last 1
    return [bool]($last -and $last.Line -match 'CLIENT CONNECTED')
  } catch { return $false }
}

# VDD must be a present, active display before we dare turn the physical panel off
function Vdd-Active { $v = Get-Vdd (Get-Mons); return ($v -and $v.Active -eq 'Yes') }

Add-Type @"
using System; using System.Runtime.InteropServices;
public static class RoamCCD { [DllImport("user32.dll")] public static extern int SetDisplayConfig(uint a,IntPtr b,uint c,IntPtr d,uint f); }
"@ -ErrorAction SilentlyContinue

# ---- AWAY: physical panel OFF, VDD becomes the sole desktop ----
function Go-Away {
  if (-not (Session-Live))  { RLog 'AWAY refused: no live Moonlight session'; return $false }
  if (-not (Vdd-Active))    { RLog 'AWAY refused: VDD not active'; return $false }
  $m=Get-Mons; $v=Get-Vdd $m; $p=Get-Phys $m $v
  if (-not $v -or -not $p)  { RLog 'AWAY refused: could not resolve VDD/physical'; return $false }
  RLog "AWAY: disabling physical $($p.Name) [$($p.'Monitor Name')], VDD=$($v.Name)"
  & $script:MMT /SetPrimary $v.Name | Out-Null; Start-Sleep -Milliseconds 600
  & $script:MMT /disable   $p.Name | Out-Null; Start-Sleep -Milliseconds 800
  $m2=Get-Mons; $v2=Get-Vdd $m2; $p2=Get-Phys $m2 $v2
  if ($v2 -and $v2.Active -eq 'Yes' -and (-not $p2 -or $p2.Active -ne 'Yes')) { RLog 'AWAY ok'; return $true }
  RLog 'AWAY verify failed -> reverting to DOCKED'; Go-Docked | Out-Null; return $false
}

# ---- DOCKED: physical panel ON + primary, VDD extended 2nd monitor ----
function Go-Docked {
  $m=Get-Mons; $v=Get-Vdd $m
  $p=$m | Where-Object { $_.Name -match '^\\\\\.\\DISPLAY' -and ($v -eq $null -or $_.Name -ne $v.Name) } | Select-Object -First 1
  if ($p) { & $script:MMT /enable $p.Name | Out-Null; Start-Sleep -Milliseconds 800 }
  # rebuild extended desktop (proven CCD: SDC_APPLY|SDC_TOPOLOGY_EXTEND = 0x84)
  [void][RoamCCD]::SetDisplayConfig(0,[IntPtr]::Zero,0,[IntPtr]::Zero,(0x80 -bor 0x04)); Start-Sleep -Milliseconds 1200
  $m2=Get-Mons; $v2=Get-Vdd $m2
  $p2=$m2 | Where-Object { $_.Name -match '^\\\\\.\\DISPLAY' -and ($v2 -eq $null -or $_.Name -ne $v2.Name) } | Select-Object -First 1
  if ($p2) { & $script:MMT /SetPrimary $p2.Name | Out-Null; Start-Sleep -Milliseconds 500 }
  RLog "DOCKED: physical=$($p2.Name) active=$($p2.Active) primary=$($p2.Primary) | VDD=$($v2.Name) active=$($v2.Active)"
  return $true
}
