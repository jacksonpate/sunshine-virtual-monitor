# ELEVATED fix: replace malformed global_prep_cmd (single \) with valid JSON (\\),
# kill crash-looping sunshine.exe, restart, verify listener comes up.
$ErrorActionPreference='Continue'
$b='C:\jacks\AI\sunshine-virtual-monitor'
$log="$b\fix-result.txt"
function L($m){ "{0}  {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -FilePath $log -Append }
"=== FIX START $(Get-Date -Format o) ===" | Set-Content $log
L ("elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))

$conf='C:\Program Files\Sunshine\config\sunshine.conf'
$good=(Get-Content "$b\_prep_line.txt" -Raw).Trim()

# sanity: the corrected value must be valid JSON before we write it
$val = $good -replace '^\s*global_prep_cmd\s*=\s*',''
try { $null=$val|ConvertFrom-Json -ErrorAction Stop; L "corrected JSON: VALID" }
catch { L "corrected JSON INVALID -> $($_.Exception.Message) ; ABORT"; "=== FIX END ABORT ===" | Tee-Object $log -Append; exit 1 }

# backup + rewrite the global_prep_cmd line
Copy-Item $conf "$conf.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
$lines = Get-Content $conf
$lines = $lines | Where-Object { $_ -notmatch '^\s*global_prep_cmd\s*=' }
$lines = @($lines) + $good
Set-Content -Path $conf -Value $lines -Encoding ASCII
L "sunshine.conf rewritten with valid-JSON global_prep_cmd"

# stop service, hard-kill any crash-looping sunshine processes, restart
try { Stop-Service SunshineService -Force -ErrorAction SilentlyContinue } catch {}
Start-Sleep 2
Get-Process sunshine,sunshinesvc -ErrorAction SilentlyContinue | ForEach-Object { try{ Stop-Process -Id $_.Id -Force }catch{} }
Start-Sleep 2
Start-Service SunshineService
L "SunshineService start issued"

# verify: sunshine.exe stays up AND a listener appears (poll up to 40s)
$ok=$false
for($i=0;$i -lt 20;$i++){
  Start-Sleep 2
  $proc = Get-Process sunshine -ErrorAction SilentlyContinue
  $port = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in 47984,47989,48010,47990
  if($proc -and $port){ $ok=$true; break }
}
$proc = Get-Process sunshine -ErrorAction SilentlyContinue
$port = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in 47984,47989,48010,47990
L ("sunshine.exe procs=" + (($proc|Measure-Object).Count) + " pids=" + (($proc.Id) -join ','))
L ("listening ports=" + (($port.LocalPort | Sort-Object -Unique) -join ','))
L ("RESULT=" + $(if($ok){'FIXED - listener up'}else{'STILL DOWN - investigate further'}))

# crash events in last 3 min?
$cr = Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=(Get-Date).AddMinutes(-3)} -ErrorAction SilentlyContinue | Where-Object Message -match 'Sunshine'
L ("post-fix Sunshine crash events (last 3min)=" + (($cr|Measure-Object).Count))
"=== FIX END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
