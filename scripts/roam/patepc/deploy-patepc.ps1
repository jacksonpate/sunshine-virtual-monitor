# deploy-patepc.ps1  (Pate-PC) - deploy the adapted roam watcher to its runtime
# location and arm it (does NOT start it; sleep-mode safe).
#
#   source  : <repo>\scripts\roam\patepc\*.ps1   (this folder)
#   runtime : C:\jacks\AI\sunshine-virtual-monitor\roam\
#
# Idempotent. Re-run any time after editing the source scripts (then
# restart-roam-watcher.ps1 to reload a running instance).
$ErrorActionPreference='Stop'
$src  = $PSScriptRoot
$roam = 'C:\jacks\AI\sunshine-virtual-monitor\roam'
New-Item -ItemType Directory -Force -Path $roam | Out-Null
$files = 'roam-lib.ps1','roam-watcher.ps1','install-roam-watcher.ps1','start-roam-watcher.ps1','restart-roam-watcher.ps1'
foreach ($f in $files) {
  Copy-Item -LiteralPath (Join-Path $src $f) -Destination (Join-Path $roam $f) -Force
  Write-Host "deployed $f -> $roam"
}
Write-Host "--- arming watcher (no start) ---"
& "$roam\install-roam-watcher.ps1"
Write-Host "--- deploy done ---"
Write-Host "Runtime: $roam"
Write-Host "Start it (only when at the desk & streaming): powershell -ExecutionPolicy Bypass -File `"$roam\start-roam-watcher.ps1`""
