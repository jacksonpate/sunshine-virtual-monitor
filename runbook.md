# Sunshine Virtual Monitor — Zephyrus (FINAL, working 2026-05-15)

Stream a virtual **second monitor** (laptop stays the main screen) via Sunshine/Moonlight
to iPad Pro / iPhone. Native Sunshine display-device handling — NO scripts.

Backlinks: [[AI/INDEX]] · memory `project_sunshine-virtual-monitor`

## Final working config — `C:\Program Files\Sunshine\config\sunshine.conf`
```
output_name = {9acddf6d-43cc-576e-9aff-0c5fc80b4cc8}
dd_configuration_option = ensure_active
dd_resolution_option = auto
dd_refresh_rate_option = auto
dd_hdr_option = disabled
dd_config_revert_delay = 3000
dd_config_revert_on_disconnect = enabled
dd_wa_hdr_toggle_delay = 500
```
- `output_name` MUST be the **device_id GUID** from `sunshine.log` startup, NEVER
  `\\.\DISPLAYn` (silently ignored → streams the laptop instead). VDD GUID
  `{9acddf6d-43cc-576e-9aff-0c5fc80b4cc8}` ("VDD by MTT"); laptop is
  `{93105fc2-99d2-5230-989e-4aea32ea6cbb}` (TL140ADXP02-0).
- `ensure_active` = laptop stays main + VDD added as extended 2nd monitor; Sunshine
  captures the VDD (per output_name). `auto` res/refresh match the connecting client.
- **`dd_hdr_option = disabled` is the color fix.** HDR on the VDD *as a secondary
  display* on this hybrid AMD iGPU + NVIDIA RTX 4050 box renders **faded/washed**
  and/or engages then drops to 8-bit SDR ("boom gone, yellow tint"). SDR 10-bit =
  correct color. HDR only ever looked right in `ensure_only_display` sole-display
  mode (laptop sleeps during stream) — documented alternative below.
- `dd_wa_hdr_toggle_delay = 500` is now **inert** (HDR disabled); harmless, left in.
- VDD driver `C:\VirtualDisplayDriver\vdd_settings.xml`: `<HDRPlus>true</HDRPlus>`
  was set during debugging. Inert while Sunshine HDR is disabled. Optional cleanup:
  set back to `false` for a pure-SDR EDID (needs VDD device reload) — not required.

## Behaviour / known tradeoffs
- Color: accurate SDR. No HDR/OLED pop (the accepted trade for dual-mode).
- HDR option (NOT in use): set `dd_configuration_option = ensure_only_display` +
  `dd_hdr_option = enabled` → gorgeous true HDR, but VDD becomes the ONLY display
  (laptop blanks during the stream) and it's true on-demand (VDD gone when idle).
- Idle/24-7: `ensure_active` does NOT do true on-demand — the VDD tends to stay an
  active monitor when not streaming. `ensure_only_display` is the only mode that
  reliably leaves idle = laptop-only (proven via fix7). If on-demand is wanted in
  dual mode, Sunshine can't do it cleanly on this box — would need external scripting
  (which is itself a footgun, see below).

## Verify
```powershell
Get-Content 'C:\Program Files\Sunshine\config\sunshine.conf'
# on connect, sunshine.log shows Capture = client res; color SDR 10-bit, holds (no
# fallback to B8G8R8A8 8-bit). Good HDR (if ever re-enabled) = R16G16B16A16_FLOAT +
# DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020.
(Get-CimInstance Win32_Service -Filter "Name='SunshineService'").StartName  # LocalSystem
```

## FOOTGUNS — do not reintroduce
1. **Cynary `global_prep_cmd`** (`setup_sunvdm.ps1`/`teardown`): single-backslash
   JSON path → Sunshine crash-loop (ucrtbase/BEX64); even valid, its convergence loop
   desyncs on this hybrid-GPU box (WindowsDisplayManager vs MultiMonitorTool name
   namespaces differ) → exit 1 → "loading desktop" timeout. Keep `global_prep_cmd`
   EMPTY. Native `dd_*` replaces it.
2. `\SunshineElevReq` task → `C:\jacks\AI\tmp\sunshine-revert.ps1` (inert) would
   demote SunshineService off LocalSystem. Never let it run.
3. Sunshine `output_name = \\.\DISPLAYn` — silently ignored; always use the GUID.

## Recovery
- No picture after a session: in-stream admin `pnputil /disable-device /deviceid <VDD>`,
  or local `DisplaySwitch /internal`, or Win+P.
- Detached internal panel (MMT `/enable` can't fix): elevated
  `fix4-extend-elevated.ps1` (CCD SetDisplayConfig SDC_TOPOLOGY_EXTEND).
- Force laptop-only baseline: CCD `SetDisplayConfig(0x80|0x01)` (internal-only),
  see `fix7-ensure-only-elevated.ps1`.

Scripts/history: `C:\jacks\AI\sunshine-virtual-monitor\` (fix1–fix12 + result logs).
Portable reproducible repo: `C:\Users\jacks\Desktop\sunshine-virtual-monitor\` (git,
branch main) + single-file `C:\Users\jacks\Desktop\sunshine-virtual-monitor.bundle`
(`git clone` it on any PC → run `scripts\deploy-new-machine.ps1` elevated; it
auto-derives that machine's per-host VDD device_id). Pushed to GitHub:
`git@github.com:jacksonpate/sunshine-virtual-monitor` (branch main). NOTE: GitHub
SSH from the Cygwin shell needs Windows OpenSSH + explicit key — repo has
`core.sshCommand` set to `C:/Windows/System32/OpenSSH/ssh.exe -i
C:/Users/jacks/.ssh/id_ed25519 -o IdentitiesOnly=yes -o IdentityAgent=none`.
The private key ACL was tightened (icacls /inheritance:r, owner-only) so Windows
OpenSSH stops rejecting it as "permissions too open".
Sunshine 2025.924, signed VDD 25.7.23 (`Root\MttVDD`), SunshineService = LocalSystem.

## Display roaming (grab-the-iPad-and-walk-away) — WORKING 2026-05-15

`C:\jacks\AI\sunshine-virtual-monitor\roam\` — always-running watcher
(`RoamDisplayWatcher` logon task, Interactive/Highest, survives reboot), zero commands:
- **DOCKED:** physical panel on (primary) + VDD = extended 2nd monitor.
- **AWAY:** physical panel off, VDD = whole desktop.

Triggers (DEEP corner = jam the literal ~18px tip, hold 3s):
- iPad **bottom-right** tip 3s → AWAY · iPad **bottom-left** tip 3s → DOCKED.
- `Ctrl+Alt+Shift+D` → DOCKED failsafe · stream drops while AWAY → auto DOCKED.
- Auto-return on desk mouse/kbd was REMOVED (Moonlight input got misclassified as
  local by the LL-hook injected flag and bounced AWAY back instantly).

Files: `roam-lib.ps1` (proven CCD+MMT transition primitives), `roam-watcher.ps1`
(LL input hooks + cursor poll + state machine; **DPI-aware** so GetCursorPos =
physical px), `install-roam-watcher-elevated.ps1` (one-time register+start),
`restart-watcher-elevated.ps1` (reload after edits). Log: `roam\roam.log`.

Gotchas: VDD rect MUST come from MultiMonitorTool `Left-Top`/`Right-Bottom` matched
by monitor name "VDD by MTT" — Forms.Screen device-name matching fails (VDD
`\\.\DISPLAYn` renumbers every topology change; AWAY still enumerates 2 screens with
the VDD as primary). `Session-Live` must scan the WHOLE sunshine.log (Sunshine writes
~200 lines after CLIENT CONNECTED; a tail window misses it → false "no session").
