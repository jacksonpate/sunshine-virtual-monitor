# Roam watcher - Pate-PC adaptation

Pate-PC-specific port of `scripts/roam/` (the upstream roam watcher was built on
**Zephyrus**, a single-panel laptop). This rig (`pate-desktop`) has **three
physical monitors + the MTT VDD**, so the two roam states are redefined per
spec:

| iPad corner (hold 3s) | State | What happens | Plain English |
|---|---|---|---|
| **bottom-LEFT**  | `ALL`  | enable `ACR0E02` + `SAM7016` + `SAM727B`, CCD extend, Acer primary, VDD stays an extended display | **"all of my monitors"** |
| **bottom-RIGHT** | `AWAY` | `/SetPrimary MTT1337`, `/disable` all 3 physical -> VDD is the whole PC | **"just the iPad display"** (== upstream clone's AWAY) |

Failsafes (unchanged from upstream): `Ctrl+Alt+Shift+D` -> `ALL`; Moonlight
session drops while `AWAY` -> `ALL`.

## Why this differs from upstream

- Upstream `Go-Docked`/`Go-Away` act on a single `\\.\DISPLAYn` physical panel.
  Here every transition acts on the **explicit Short Monitor IDs** that
  `moonlight-setup\scripts\privacy-on.ps1` / `privacy-off.ps1` already prove
  work on this box. That also sidesteps runbook FOOTGUN #3 (`\\.\DISPLAYn`
  renumbers on every topology change - never key off it).
- `Go-Away` == privacy-on's MMT calls + upstream safety gates (Session-Live,
  Vdd-Active, verify, auto-revert to `ALL` on failure).
- `Go-All` == privacy-off's MMT calls + a CCD `SDC_TOPOLOGY_EXTEND` rebuild so
  the VDD is re-attached as an extended monitor and the iPad keeps streaming.

## Integration with the existing Sunshine setup

`apps.json` "Desktop" still runs `privacy-on.ps1` on connect (VDD-only = the
`AWAY` start state) and `privacy-off.ps1` on disconnect (all physical back =
failsafe). The watcher only layers *in-session* corner toggling on top, using
the same MMT + same Short Monitor IDs, so the two never fight. `sunshine.conf`
(`output_name = {5eb52002-659f-5729-bdd8-9cdc4efd1bf5}`) and `apps.json` are
unchanged - they were already correct.

## Files

| File | Role |
|---|---|
| `roam-lib.ps1`            | transition primitives (`Go-All`, `Go-Away`, helpers) |
| `roam-watcher.ps1`        | always-running state machine + LL input hooks (single-instance via a real `createdNew` mutex) |
| `install-roam-watcher.ps1`| register the `RoamDisplayWatcher` AtLogon task (no admin needed; `-Start` to also start now) |
| `start-roam-watcher.ps1`  | start the watcher now (use at the desk while streaming) |
| `restart-roam-watcher.ps1`| reload after editing the scripts |
| `deploy-patepc.ps1`       | copy these to the runtime dir + arm (no start) |

- **Source of truth:** this folder (in the git repo).
- **Runtime:** `C:\jacks\AI\sunshine-virtual-monitor\roam\` (where the task
  points; `roam.log` is written here).

## Deploy / operate

```powershell
# deploy + arm (idempotent; does NOT start - safe any time incl. sleep mode)
powershell -ExecutionPolicy Bypass -File scripts\roam\patepc\deploy-patepc.ps1

# start it (ONLY at the desk while streaming - it rebuilds display topology)
powershell -ExecutionPolicy Bypass -File C:\jacks\AI\sunshine-virtual-monitor\roam\start-roam-watcher.ps1

# after editing roam-*.ps1: re-deploy then reload the running instance
powershell -ExecutionPolicy Bypass -File scripts\roam\patepc\deploy-patepc.ps1
powershell -ExecutionPolicy Bypass -File C:\jacks\AI\sunshine-virtual-monitor\roam\restart-roam-watcher.ps1
```

The AtLogon scheduled task is registered at **RunLevel Limited** (no admin):
MMT enable/disable, CCD `SetDisplayConfig`, and the `WH_*_LL` hooks all work at
Limited in the user's own interactive session - the upstream clone used
`Highest` only defensively. If you ever re-run `install-roam-watcher.ps1` from
an **elevated** shell it auto-upgrades the task to `Highest`.

## Status as deployed 2026-05-16

Deployed + armed; **not started** (deployed during sleep mode - starting it
would rebuild topology and disturb the dim overlays). It auto-starts at the
next logon, or run `start-roam-watcher.ps1` at the desk while streaming.

Verified without a live session (sleep mode, no iPad connected): all 6 scripts
parse clean and pure-ASCII; task registered (State=Ready, Limited, AtLogon,
Interactive) pointing at the deployed watcher; read-only helpers resolve the
live topology correctly (`Vdd-Row MTT1337` -> "VDD by MTT" 2420x1668,
`Session-Live`/`AnyPhys-Active` correct). **Still to verify live:** the actual
`Go-All`/`Go-Away` topology transitions and the iPad corner-dwell triggers -
do this from the iPad once streaming (it needs physical monitor toggling, which
must not happen during sleep mode).
