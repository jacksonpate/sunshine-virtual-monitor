# One-shot: grant the Zephyrus Claude session SSH admin access to THIS machine.
# Ensures an OpenSSH server is running and installs the Zephyrus public key into
# every plausible authorized_keys (incl. Windows admin path with correct ACL).
# Run ELEVATED (via the Sunshine app "run as admin" checkbox).
$ErrorActionPreference = 'SilentlyContinue'
$log = "$env:USERPROFILE\grant-ssh-result.txt"
"=== GRANT-SSH $(Get-Date -o) ===" | Set-Content $log
$pub = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMD1natAgQwBfeCVriXvGfZhkqQ8BRF9fVTvbwVvF2Q1 pate-pc-to-zephyrus'

# 1. Windows OpenSSH server present + auto + running (harmless if a Cygwin sshd already owns 22)
try {
  if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
  }
  Set-Service sshd -StartupType Automatic
  Start-Service sshd
  "sshd: $((Get-Service sshd).Status)" | Add-Content $log
} catch { "sshd: $_" | Add-Content $log }

# 2. firewall open for 22
New-NetFirewallRule -Name claude-sshd-22 -DisplayName 'OpenSSH 22 (Claude)' -Enabled True `
  -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue | Out-Null

# 3. install the key everywhere it might be read
function Add-Key($path){
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  $cur = if (Test-Path $path) { Get-Content $path -Raw } else { '' }
  if ($cur -notmatch [regex]::Escape($pub)) { Add-Content -Path $path -Value $pub }
  "key -> $path" | Add-Content $log
}
Add-Key "$env:USERPROFILE\.ssh\authorized_keys"
$admAK = "$env:ProgramData\ssh\administrators_authorized_keys"
Add-Key $admAK
# Windows OpenSSH requires admin authorized_keys be owned by Administrators/SYSTEM only
icacls $admAK /inheritance:r 2>&1 | Out-Null
icacls $admAK /grant 'Administrators:F' 'SYSTEM:F' 2>&1 | Out-Null
if (Test-Path 'C:\cygwin64\home') {
  Get-ChildItem 'C:\cygwin64\home' -Directory | ForEach-Object { Add-Key "$($_.FullName)\.ssh\authorized_keys" }
}

# 4. report what's actually serving 22
$own = (Get-NetTCPConnection -State Listen -LocalPort 22 -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
"port22 -> pid $own ($((Get-Process -Id $own -ErrorAction SilentlyContinue).Name))" | Add-Content $log
"whoami: $(whoami)" | Add-Content $log
"=== DONE ===" | Add-Content $log
