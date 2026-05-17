# Emergency recovery for a host whose Sunshine stream went black after deploy.
# Makes Sunshine capture the DEFAULT PRIMARY display (where login/desktop renders)
# by clearing output_name and removing dd_/global_prep_cmd, then restarts Sunshine.
# Safe: backs up the current (broken) config first; restore-result log written.
$ErrorActionPreference = 'SilentlyContinue'
$d = 'C:\Program Files\Sunshine\config'
$c = "$d\sunshine.conf"
$log = "$d\recover-result.txt"
"=== RECOVER $(Get-Date -o) ===" | Set-Content $log
if (Test-Path $c) {
  Copy-Item $c "$d\sunshine.conf.broken-$(Get-Date -f yyyyMMddHHmmss)" -Force
  $keep = Get-Content $c | Where-Object { $_ -notmatch '^\s*(output_name|dd_|global_prep_cmd)\s*=' }
  $keep | Set-Content $c -Encoding ASCII
  "rewrote sunshine.conf (output_name cleared; dd_/global_prep_cmd removed)" | Add-Content $log
  Get-Content $c | Add-Content $log
} else { "sunshine.conf NOT FOUND at $c" | Add-Content $log }
Restart-Service SunshineService -Force
"restarted SunshineService" | Add-Content $log
