# roam-watcher.ps1  (Pate-PC / pate-desktop) - always-running display roaming daemon.
#   iPad bottom-LEFT  3s  -> ALL   (all 3 physical monitors ON, VDD extended)  "all of my monitors"
#   iPad bottom-RIGHT 3s  -> AWAY  (all physical OFF, VDD = whole PC)          "just the iPad" (== upstream clone)
#   Ctrl+Alt+Shift+D      -> ALL   (failsafe)
#   Moonlight session ends while AWAY -> ALL (failsafe restore desk)
# Runs in the interactive session via a logon scheduled task (or Startup
# launcher). Single-instance via a global mutex. Fails safe to ALL.
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\roam-lib.ps1"
$createdNew = $false
$single = New-Object System.Threading.Mutex($true,'Global\RoamWatcherSingleton',[ref]$createdNew)
if (-not $createdNew) { return }   # another watcher instance already owns the singleton
RLog "=== watcher start (pid $PID) Pate-PC ==="

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

# DPI-aware so GetCursorPos returns PHYSICAL pixels matching MMT geometry.
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class RoamDpi {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue
try { [void][RoamDpi]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch { try { [void][RoamDpi]::SetProcessDPIAware() } catch {} }

# VDD rect straight from MultiMonitorTool, pinned by Short Monitor ID (MTT1337).
# Renumber-proof, role-proof, state-proof.
function Vdd-Rect {
  $v = Vdd-Row (Get-Mons)
  if (-not $v) { return $null }
  $lt = @(($v.'Left-Top'    -split ',') | ForEach-Object { [int]($_.Trim()) })
  $rb = @(($v.'Right-Bottom' -split ',') | ForEach-Object { [int]($_.Trim()) })
  if ($lt.Count -lt 2 -or $rb.Count -lt 2) { return $null }
  [pscustomobject]@{ L=$lt[0]; T=$lt[1]; R=$rb[0]; B=$rb[1]; Act=$v.Active }
}

# initial state from current topology (by Short Monitor ID).
#   any physical active        -> ALL
#   none physical, VDD + live  -> AWAY  (Sunshine privacy-on connect default)
#   otherwise                  -> ALL
if (AnyPhys-Active) { $state = 'ALL' }
elseif ((Vdd-Active) -and (Session-Live)) { $state = 'AWAY' }
else { $state = 'ALL' }
RLog "initial state=$state"
if ($state -eq 'AWAY' -and -not (Session-Live)) { Go-All | Out-Null; $state='ALL' }

$CORNER = 18            # DEEP corner - jam the very tip (physical px)
$DWELL  = 3000          # ms hold
$lastDbg = 0
$prevState = $state
$rect = Vdd-Rect; $rectAge = [Environment]::TickCount
if ($rect) { RLog "rect[$state] L=$($rect.L) T=$($rect.T) R=$($rect.R) B=$($rect.B) act=$($rect.Act)" }
$brEnter = 0; $blEnter = 0
$awaySince = [Environment]::TickCount

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

    # ---- failsafe: hotkey or dropped session while AWAY -> ALL ----
    if ($state -eq 'AWAY') {
      if ([RoamHooks]::HotkeyDock) { RLog 'hotkey -> ALL'; Go-All|Out-Null; $state='ALL'; [RoamHooks]::HotkeyDock=$false; $brEnter=0;$blEnter=0; continue }
      if (-not (Session-Live)) { RLog 'session ended while AWAY -> ALL'; Go-All|Out-Null; $state='ALL'; continue }
    } else { [RoamHooks]::HotkeyDock=$false }

    if (-not $rect) { continue }
    $inBR = ($pt.X -ge $rect.R-$CORNER -and $pt.X -le $rect.R -and $pt.Y -ge $rect.B-$CORNER -and $pt.Y -le $rect.B)
    $inBL = ($pt.X -ge $rect.L -and $pt.X -le $rect.L+$CORNER -and $pt.Y -ge $rect.B-$CORNER -and $pt.Y -le $rect.B)
    if ($pt.Y -ge $rect.B-120 -and ($now - $lastDbg) -gt 1500) {
      RLog "cur=$($pt.X),$($pt.Y) rect[$state] L=$($rect.L) R=$($rect.R) B=$($rect.B) BL=$inBL BR=$inBR"; $lastDbg=$now }

    # ---- ALL + bottom-RIGHT dwell -> AWAY (just the iPad) ----
    if ($state -eq 'ALL') {
      if ($inBR) { if ($brEnter -eq 0){$brEnter=$now}
        elseif ($now-$brEnter -ge $DWELL) {
          RLog 'BR dwell -> AWAY'; if (Go-Away) { $state='AWAY'; $awaySince=[Environment]::TickCount; [RoamHooks]::LastRealInputTick=0 }
          $brEnter=0 }
      } else { $brEnter=0 }
    }
    # ---- AWAY + bottom-LEFT dwell -> ALL (all of my monitors) ----
    if ($state -eq 'AWAY') {
      if ($inBL) { if ($blEnter -eq 0){$blEnter=$now}
        elseif ($now-$blEnter -ge $DWELL) { RLog 'BL dwell -> ALL'; Go-All|Out-Null; $state='ALL'; $blEnter=0 }
      } else { $blEnter=0 }
    }
  } catch { RLog "loop err: $_" }
}
