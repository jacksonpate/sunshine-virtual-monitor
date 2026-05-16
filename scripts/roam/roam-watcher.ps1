# roam-watcher.ps1 — always-running display roaming daemon.
#   iPad bottom-RIGHT 3s  -> AWAY  (physical off, VDD = whole PC)
#   iPad bottom-LEFT  3s  -> DOCKED
#   real desk kbd/mouse   -> auto DOCKED (non-injected input)
#   Ctrl+Alt+Shift+D      -> DOCKED (failsafe)
# Runs in the interactive session via a logon scheduled task. Fails safe to DOCKED.
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\roam-lib.ps1"
$single = New-Object System.Threading.Mutex($true,'Global\RoamWatcherSingleton',[ref]$null)
RLog "=== watcher start (pid $PID) ==="

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class RoamHooks {
  public static volatile int  LastRealInputTick = 0;
  public static volatile bool HotkeyDock        = false;
  [StructLayout(LayoutKind.Sequential)] struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] struct MSLL  { public POINT pt; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KBLL  { public uint vk, sc, flags, time; public IntPtr extra; }
  delegate IntPtr HookProc(int code, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, HookProc cb, IntPtr mod, uint t);
  [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int c, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern int  GetMessage(out MSG m, IntPtr h, uint a, uint b);
  [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
  [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr h; public uint m; public IntPtr w,l; public uint t; public POINT p; }
  const int WH_MOUSE_LL=14, WH_KEYBOARD_LL=13;
  const uint LLMHF_INJECTED=0x1, LLKHF_INJECTED=0x10;
  static HookProc _m, _k; static IntPtr _mh, _kh;
  static bool ctrl, alt, shift;
  static IntPtr MouseCb(int code, IntPtr w, IntPtr l){
    if(code>=0){ MSLL d=(MSLL)Marshal.PtrToStructure(l,typeof(MSLL));
      if((d.flags & LLMHF_INJECTED)==0) LastRealInputTick=Environment.TickCount; }
    return CallNextHookEx(_mh,code,w,l);
  }
  static IntPtr KeyCb(int code, IntPtr w, IntPtr l){
    if(code>=0){ KBLL d=(KBLL)Marshal.PtrToStructure(l,typeof(KBLL));
      bool inj=(d.flags & LLKHF_INJECTED)!=0;
      bool down=(w==(IntPtr)0x100 || w==(IntPtr)0x104); // WM_KEYDOWN/SYSKEYDOWN
      bool up  =(w==(IntPtr)0x101 || w==(IntPtr)0x105);
      int vk=(int)d.vk;
      if(vk==162||vk==163) ctrl=down?true:(up?false:ctrl);
      if(vk==164||vk==165) alt =down?true:(up?false:alt);
      if(vk==160||vk==161) shift=down?true:(up?false:shift);
      if(!inj){ LastRealInputTick=Environment.TickCount;
        if(down && vk==0x44 && ctrl && alt && shift) HotkeyDock=true; } // Ctrl+Alt+Shift+D
    }
    return CallNextHookEx(_kh,code,w,l);
  }
  public static void Start(){
    var t=new Thread(()=>{ IntPtr h=GetModuleHandle(null);
      _m=MouseCb; _k=KeyCb;
      _mh=SetWindowsHookEx(WH_MOUSE_LL,_m,h,0);
      _kh=SetWindowsHookEx(WH_KEYBOARD_LL,_k,h,0);
      MSG msg; while(GetMessage(out msg,IntPtr.Zero,0,0)>0){}
    }); t.IsBackground=true; t.Start();
  }
}
public static class RoamCur {
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int X,Y; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out PT p);
}
"@ -ErrorAction SilentlyContinue

[RoamHooks]::Start()

# Make the process DPI-aware so GetCursorPos returns PHYSICAL pixels that match
# MultiMonitorTool's reported geometry (otherwise cursor is scaled, rect is not).
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class RoamDpi {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue
try { [void][RoamDpi]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch { try { [void][RoamDpi]::SetProcessDPIAware() } catch {} }

# VDD rect straight from MultiMonitorTool — it pins the VDD by monitor name and
# gives exact physical-pixel geometry. Renumber-proof, role-proof, state-proof.
function Vdd-Rect {
  $v = Get-Vdd (Get-Mons)
  if (-not $v) { return $null }
  $lt = @(($v.'Left-Top'    -split ',') | ForEach-Object { [int]($_.Trim()) })
  $rb = @(($v.'Right-Bottom' -split ',') | ForEach-Object { [int]($_.Trim()) })
  if ($lt.Count -lt 2 -or $rb.Count -lt 2) { return $null }
  [pscustomobject]@{ L=$lt[0]; T=$lt[1]; R=$rb[0]; B=$rb[1]; Act=$v.Active }
}

# initial state from current topology
$m0=Get-Mons; $v0=Get-Vdd $m0
$p0=$m0 | Where-Object { $_.Name -match '^\\\\\.\\DISPLAY' -and ($v0 -eq $null -or $_.Name -ne $v0.Name) } | Select-Object -First 1
$state = if ($p0 -and $p0.Active -eq 'Yes') { 'DOCKED' } else { if ($v0 -and $v0.Active -eq 'Yes' -and (Session-Live)) {'AWAY'} else { 'DOCKED' } }
RLog "initial state=$state"
if ($state -eq 'AWAY' -and -not (Session-Live)) { Go-Docked|Out-Null; $state='DOCKED' }

$CORNER = 18            # DEEP corner — must jam into the very tip (physical px)
$DWELL  = 3000          # ms hold
$lastDbg = 0
$prevState = $state
$rect = Vdd-Rect; $rectAge = [Environment]::TickCount
if ($rect) { RLog "rect[$state] L=$($rect.L) T=$($rect.T) R=$($rect.R) B=$($rect.B) act=$($rect.Act)" }
$brEnter = 0; $blEnter = 0
$awaySince = [Environment]::TickCount   # ignore stale pre-existing real input

while ($true) {
  Start-Sleep -Milliseconds 300
  try {
    if ($state -ne $prevState) {
      $rect = Vdd-Rect; $rectAge=[Environment]::TickCount; $prevState=$state
      if ($rect) { RLog "rect[$state] L=$($rect.L) T=$($rect.T) R=$($rect.R) B=$($rect.B) act=$($rect.Act)" }
    }
    elseif ([Environment]::TickCount - $rectAge -gt 2500) { $rect = Vdd-Rect; $rectAge=[Environment]::TickCount }
    $pt = New-Object RoamCur+PT; [void][RoamCur]::GetCursorPos([ref]$pt)
    $now=[Environment]::TickCount

    # ---- failsafe: hotkey or real desk input while AWAY -> DOCKED ----
    if ($state -eq 'AWAY') {
      # (auto-return on desk mouse/keyboard removed per request — Moonlight input was
      #  being misread as local and bouncing AWAY back instantly.)
      if ([RoamHooks]::HotkeyDock) { RLog 'hotkey -> DOCKED'; Go-Docked|Out-Null; $state='DOCKED'; [RoamHooks]::HotkeyDock=$false; $brEnter=0;$blEnter=0; continue }
      if (-not (Session-Live)) { RLog 'session ended while AWAY -> DOCKED'; Go-Docked|Out-Null; $state='DOCKED'; continue }
    } else { [RoamHooks]::HotkeyDock=$false }

    if (-not $rect) { continue }
    $inBR = ($pt.X -ge $rect.R-$CORNER -and $pt.X -le $rect.R -and $pt.Y -ge $rect.B-$CORNER -and $pt.Y -le $rect.B)
    $inBL = ($pt.X -ge $rect.L -and $pt.X -le $rect.L+$CORNER -and $pt.Y -ge $rect.B-$CORNER -and $pt.Y -le $rect.B)
    # diagnostic: when near the bottom edge, log where the cursor actually is (throttled)
    if ($pt.Y -ge $rect.B-120 -and ($now - $lastDbg) -gt 1500) {
      RLog "cur=$($pt.X),$($pt.Y) rect[$state] L=$($rect.L) R=$($rect.R) B=$($rect.B) BL=$inBL BR=$inBR"; $lastDbg=$now }

    # ---- DOCKED + bottom-right dwell -> AWAY ----
    if ($state -eq 'DOCKED') {
      if ($inBR) { if ($brEnter -eq 0){$brEnter=$now}
        elseif ($now-$brEnter -ge $DWELL) {
          RLog 'BR dwell -> AWAY'; if (Go-Away) { $state='AWAY'; $awaySince=[Environment]::TickCount; [RoamHooks]::LastRealInputTick=0 }
          $brEnter=0 }
      } else { $brEnter=0 }
    }
    # ---- AWAY + bottom-left dwell -> DOCKED ----
    if ($state -eq 'AWAY') {
      if ($inBL) { if ($blEnter -eq 0){$blEnter=$now}
        elseif ($now-$blEnter -ge $DWELL) { RLog 'BL dwell -> DOCKED'; Go-Docked|Out-Null; $state='DOCKED'; $blEnter=0 }
      } else { $blEnter=0 }
    }
  } catch { RLog "loop err: $_" }
}
