# Sunshine Virtual Monitor — portable setup

Stream a **virtual second monitor** from a Windows host to a Moonlight client
(iPad / iPhone / etc.) using [Sunshine](https://github.com/LizardByte/Sunshine)
+ the signed [Virtual Display Driver](https://github.com/VirtualDrivers/Virtual-Display-Driver),
driven entirely by **Sunshine's native display-device handling — no helper scripts
wired into Sunshine**.

Behaviour: your laptop/PC screen stays your normal main display; the VDD shows up
as an extra extended monitor that Sunshine captures and streams; resolution/refresh
auto-match whatever client connects.

Originally built/debugged on a hybrid-GPU laptop (AMD iGPU + NVIDIA RTX 4050,
Windows 11, Sunshine 2025.924). Works on any Windows 10/11 box.

---

## Deploy on a new computer (one command)

> **Why a script and not just copy the config:** Sunshine's `output_name` on
> Windows must be the display's **`device_id` GUID**, which is **unique per
> machine**. Copying `config/sunshine.conf` verbatim will stream the wrong
> display. `deploy-new-machine.ps1` installs the driver and then auto-derives the
> new machine's VDD GUID from Sunshine's own logs and writes the config correctly.

Prerequisites on the target PC:
- Windows 10/11 (x64; ARM64 driver also bundled).
- [Sunshine](https://github.com/LizardByte/Sunshine) installed and its service
  running (`SunshineService`).
- A Moonlight client to test from.

Then, from an **elevated** PowerShell in the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-new-machine.ps1
```

It will: install the signed VDD driver + create the `Root\MttVDD` device, drop
`vdd_settings.xml` into `C:\VirtualDisplayDriver\`, restart Sunshine, read the new
machine's VDD `device_id` from `sunshine.log`, write a correct `sunshine.conf`,
restart Sunshine again, and verify. Then connect from Moonlight.

---

## Final working configuration

`config/sunshine.conf` (the `output_name` GUID shown is host-specific — the deploy
script replaces it for the target machine):

```
output_name = {VDD-device_id-guid}      # the VDD ("VDD by MTT"), NOT \\.\DISPLAYn
dd_configuration_option = ensure_active  # host screen stays main; VDD = 2nd monitor
dd_resolution_option = auto              # match the connecting client
dd_refresh_rate_option = auto
dd_hdr_option = disabled                 # see HDR note below
dd_config_revert_delay = 3000
dd_config_revert_on_disconnect = enabled
dd_wa_hdr_toggle_delay = 500             # inert while HDR disabled
```

`config/vdd_settings.xml` → goes to `C:\VirtualDisplayDriver\vdd_settings.xml`
(`<HDRPlus>true</HDRPlus>` set; inert while Sunshine HDR is disabled).

---

## Important notes / hard-won lessons

- **`output_name` must be the `device_id` GUID, never `\\.\DISPLAYn`.** The
  `\\.\DISPLAYn` value is silently ignored by modern Sunshine and it falls back to
  streaming the primary (your real screen). `dxgi-info.exe` prints the misleading
  `\\.\DISPLAYn`; the real GUID is in `sunshine.log` at startup
  (`"device_id": "{...}", "friendly_name": "VDD by MTT"`). The deploy script handles
  this.
- **HDR as a *secondary* VDD washes out / drops to SDR** on a hybrid-GPU host —
  faded, yellow-tinted, or engages then "boom gone". Streaming SDR 10-bit
  (`dd_hdr_option = disabled`) gives correct color. True HDR only looks right with
  `dd_configuration_option = ensure_only_display` (VDD becomes the *only* display —
  host screen blanks during the stream — but it's true on-demand and HDR is clean).
  Pick your trade; default here is accurate-color dual.
- **`ensure_active` is not true on-demand** — the VDD tends to stay an active
  monitor when idle. Only `ensure_only_display` reliably leaves idle = host-only.
- **FOOTGUN — do not wire `scripts/setup_sunvdm.ps1` / `teardown_sunvdm.ps1` into
  Sunshine's `global_prep_cmd`.** That third-party (Cynary) approach crash-loops
  Sunshine if the path is single-backslash JSON, and its display-convergence loop
  desyncs on hybrid-GPU hosts. They're kept here only as history. The native `dd_*`
  options replace them entirely. Keep `global_prep_cmd` empty.

See `runbook.md` for the full operational doc, recovery steps, and the complete
debugging history. `history/` holds the run logs from the original build.

---

## Repo layout

| Path | What |
|---|---|
| `scripts/deploy-new-machine.ps1` | one-shot bootstrap for a fresh PC |
| `scripts/install-svm-elevated.ps1` | original VDD-driver installer |
| `scripts/fix*.ps1` | the iterative fixes (history + recovery, e.g. `fix4` = rebuild extended desktop) |
| `scripts/set-vdd-scale.ps1` | per-monitor DPI scaling helper (DisplayConfig API) |
| `scripts/setup_sunvdm.ps1`, `teardown_sunvdm.ps1` | abandoned Cynary approach — do not use |
| `driver/SignedDrivers/` | signed VDD 25.7.23 (x64 under `x86/`, plus ARM64, and the virtual audio driver) |
| `driver/Dependencies/devcon.exe` | used to create the `Root\MttVDD` device |
| `tools/multimonitortool-x64/`, `tools/vsynctoggle*` | recovery / legacy helpers |
| `config/` | the working `sunshine.conf` + `vdd_settings.xml` |
| `runbook.md` | canonical operational runbook |
| `history/` | result logs from the original build/debug session |
