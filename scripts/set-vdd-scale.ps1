# Set per-monitor DPI scaling for the VDD only (live, no logoff) via the
# undocumented DisplayConfig DPI API. Target = 150% (arg overrides).
param([int]$TargetPct = 150)
$ErrorActionPreference = 'Stop'
$LOG = 'C:\jacks\AI\sunshine-virtual-monitor\scale-result.txt'
"=== SCALE START $(Get-Date -Format o) target=$TargetPct% sid=$([System.Diagnostics.Process]::GetCurrentProcess().SessionId) ===" | Set-Content $LOG
function Write-Host { param([Parameter(ValueFromRemainingArguments=$true)]$m) ($m -join ' ') | Tee-Object -FilePath $LOG -Append }
trap { "ERROR: $_" | Tee-Object -FilePath $LOG -Append; "=== SCALE END (error) ===" | Add-Content $LOG; exit 1 }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class DPI {
  [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint Low; public int High; }
  [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint Num; public uint Den; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeIdx; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_TARGET {
    public LUID adapterId; public uint id; public uint modeIdx; public uint outTech;
    public uint rotation; public uint scaling; public RATIONAL refresh; public uint scanline;
    public int targetAvailable; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_INFO { public PATH_SOURCE src; public PATH_TARGET tgt; public uint flags; }
  [StructLayout(LayoutKind.Sequential, Size=64)] public struct MODE_INFO { }
  [StructLayout(LayoutKind.Sequential)] public struct HEADER { public uint type; public uint size; public LUID adapterId; public uint id; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct SOURCE_NAME {
    public HEADER header;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string gdiName; }
  [StructLayout(LayoutKind.Sequential)] public struct DPI_GET { public HEADER header; public int min; public int cur; public int max; }
  [StructLayout(LayoutKind.Sequential)] public struct DPI_SET { public HEADER header; public int rel; }

  [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint np, out uint nm);
  [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint np, [Out] PATH_INFO[] pa, ref uint nm, [Out] MODE_INFO[] ma, IntPtr topo);
  [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref SOURCE_NAME r);
  [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref DPI_GET r);
  [DllImport("user32.dll")] public static extern int DisplayConfigSetDeviceInfo(ref DPI_SET r);
}
"@

$QDC_ONLY_ACTIVE = 0x12   # ONLY_ACTIVE_PATHS | VIRTUAL_MODE_AWARE
$GET_SOURCE_NAME = 1
$GET_DPI = [uint32]'0xFFFFFFFD'   # undocumented
$SET_DPI = [uint32]'0xFFFFFFFC'   # undocumented
$dpiVals = 100,125,150,175,200,225,250,300,350,400,450,500

[uint32]$np=0; [uint32]$nm=0
[void][DPI]::GetDisplayConfigBufferSizes($QDC_ONLY_ACTIVE,[ref]$np,[ref]$nm)
$paths = New-Object 'DPI+PATH_INFO[]' $np
$modes = New-Object 'DPI+MODE_INFO[]' $nm
$rc = [DPI]::QueryDisplayConfig($QDC_ONLY_ACTIVE,[ref]$np,$paths,[ref]$nm,$modes,[IntPtr]::Zero)
Write-Host ("QueryDisplayConfig rc={0} np={1} nm={2}" -f $rc,$np,$nm)
if ($rc -ne 0) { throw "QueryDisplayConfig failed rc=$rc" }

$done=$false
for ($i=0; $i -lt $np; $i++) {
  $p = $paths[$i]
  $sn = New-Object 'DPI+SOURCE_NAME'
  $sn.header.type = $GET_SOURCE_NAME
  $sn.header.size = [Runtime.InteropServices.Marshal]::SizeOf([type]'DPI+SOURCE_NAME')
  $sn.header.adapterId = $p.src.adapterId
  $sn.header.id = $p.src.id
  $snrc = [DPI]::DisplayConfigGetDeviceInfo([ref]$sn)
  Write-Host ("path[{0}] srcId={1} snrc={2} gdi='{3}'" -f $i,$p.src.id,$snrc,$sn.gdiName)
  if ($snrc -ne 0) { continue }
  if ($sn.gdiName -ne '\\.\DISPLAY11') { continue }

  $g = New-Object 'DPI+DPI_GET'
  $g.header.type = $GET_DPI
  $g.header.size = [Runtime.InteropServices.Marshal]::SizeOf([type]'DPI+DPI_GET')
  $g.header.adapterId = $p.src.adapterId
  $g.header.id = $p.src.id
  if ([DPI]::DisplayConfigGetDeviceInfo([ref]$g) -ne 0) { throw "DPI GET failed" }

  $minAbs = [math]::Abs($g.min)
  $curIdx = $minAbs + $g.cur
  $recIdx = $minAbs
  Write-Host ("VDD scaling: current={0}% recommended={1}% (rel min={2} cur={3} max={4})" -f $dpiVals[$curIdx],$dpiVals[$recIdx],$g.min,$g.cur,$g.max)

  # pick exact target % or nearest reachable
  $tIdx = [Array]::IndexOf($dpiVals,$TargetPct)
  if ($tIdx -lt 0) { $tIdx = ($dpiVals | ForEach-Object {[math]::Abs($_-$TargetPct)} | Sort-Object)[0]; $tIdx=[Array]::IndexOf(($dpiVals|ForEach-Object{[math]::Abs($_-$TargetPct)}),($dpiVals|ForEach-Object{[math]::Abs($_-$TargetPct)}|Measure-Object -Min).Minimum) }
  $rel = $tIdx - $minAbs
  if ($rel -lt $g.min) { $rel = $g.min }
  if ($rel -gt $g.max) { $rel = $g.max }

  $s = New-Object 'DPI+DPI_SET'
  $s.header.type = $SET_DPI
  $s.header.size = [Runtime.InteropServices.Marshal]::SizeOf([type]'DPI+DPI_SET')
  $s.header.adapterId = $p.src.adapterId
  $s.header.id = $p.src.id
  $s.rel = $rel
  if ([DPI]::DisplayConfigSetDeviceInfo([ref]$s) -ne 0) { throw "DPI SET failed" }

  Start-Sleep -Milliseconds 800
  $g2 = New-Object 'DPI+DPI_GET'
  $g2.header.type = $GET_DPI
  $g2.header.size = [Runtime.InteropServices.Marshal]::SizeOf([type]'DPI+DPI_GET')
  $g2.header.adapterId = $p.src.adapterId
  $g2.header.id = $p.src.id
  [void][DPI]::DisplayConfigGetDeviceInfo([ref]$g2)
  $newIdx = [math]::Abs($g2.min) + $g2.cur
  Write-Host ("VDD scaling NOW = {0}%  (requested {1}%)" -f $dpiVals[$newIdx],$TargetPct)
  $done=$true
  break
}
if (-not $done) { throw "VDD display not found among active paths" }
"=== SCALE END (ok) ===" | Add-Content $LOG
