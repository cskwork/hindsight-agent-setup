# Hindsight shared memory for Claude Code, Codex, Hermes and Pi on Windows — no Docker.
# Idempotent: safe to re-run. Auto-start uses per-user Scheduled Tasks (at logon).
# Usage:  powershell -ExecutionPolicy Bypass -File .\install.ps1
$ErrorActionPreference = 'Stop'

function Env-Or($name, $default) { $v = [Environment]::GetEnvironmentVariable($name); if ($v) { $v } else { $default } }
$Model     = Env-Or 'HINDSIGHT_MODEL'     ''   # empty = cheapest Codex model on your plan (luna > mini)
$Reasoning = Env-Or 'HINDSIGHT_REASONING' 'low'
$Fallback  = Env-Or 'HINDSIGHT_FALLBACK_MODEL' 'claude-haiku-4-5'   # used via your Claude login while the Codex model is rate-limited; none = off
$Bank      = Env-Or 'HINDSIGHT_BANK'      'agents'
$Port      = Env-Or 'HINDSIGHT_PORT'      '8888'
$UiPort    = Env-Or 'HINDSIGHT_UI_PORT'   '9999'
$Ui        = Env-Or 'HINDSIGHT_UI'        '1'
$Agents    = (Env-Or 'HINDSIGHT_AGENTS'   'claude-code codex hermes pi') -split '\s+'
$PiPackage = Env-Or 'HINDSIGHT_PI_PACKAGE' 'git:github.com/cskwork/pi-hindsight-memory'   # loads Hindsight's official Pi adapter

$HomeDir      = Join-Path $HOME '.hindsight'
$CodexHomeDir = Join-Path $HomeDir 'codex-home'   # separate ChatGPT login so token refreshes never log out your own Codex
$LogDir       = Join-Path $HomeDir 'logs'
$ApiUrl       = "http://127.0.0.1:$Port"
$TaskServer   = 'Hindsight Server'
$TaskUi       = 'Hindsight UI'

function Say($m)  { Write-Host "`n==> $m" }
function Fail($m) { Write-Host "`nERROR: $m" -ForegroundColor Red; exit 1 }
function Has($c)  { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Write-Utf8($path, $text) { [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false)) }
function Backup($path) { if (Test-Path $path) { Copy-Item $path "$path.bak-hindsight-$(Get-Date -Format yyyyMMddHHmmss)" } }
function Stop-Port($p) {
  Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
}

# 1. Prerequisites -----------------------------------------------------------
Say 'Checking prerequisites'
if (-not (Has uv))    { Fail 'uv is required: powershell -c "irm https://astral.sh/uv/install.ps1 | iex"' }
if (-not (Has node))  { Fail 'node (>=18) is required for the Claude Code / Codex integration' }
if (-not (Has npx))   { Fail 'npx is required' }
if (-not (Has codex)) { Fail 'codex CLI is required for the ChatGPT login: npm i -g @openai/codex' }

# 2. Server install ----------------------------------------------------------
Say 'Installing hindsight-api (uv tool)'
uv tool install --upgrade hindsight-api | Out-Null
$ServerExe = Join-Path (uv tool dir --bin).Trim() 'hindsight-api.exe'
if (-not (Test-Path $ServerExe)) { Fail "hindsight-api not found at $ServerExe" }
New-Item -ItemType Directory -Force -Path $LogDir, $CodexHomeDir | Out-Null

# 3. Dedicated ChatGPT login for the server ----------------------------------
$env:CODEX_HOME = $CodexHomeDir
codex login status *> $null
if ($LASTEXITCODE -ne 0) {
  Say 'The memory server needs its own ChatGPT login (one time)'
  if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) { codex login }
  else { Fail "No interactive console. Run this yourself, then re-run install.ps1:  `$env:CODEX_HOME='$CodexHomeDir'; codex login" }
  codex login status *> $null
  if ($LASTEXITCODE -ne 0) { Fail 'ChatGPT login did not complete' }
}
Remove-Item Env:CODEX_HOME

if (-not $Model) {
  # Codex keeps the plan's model list in models_cache.json; prefer the newest *luna*, then *mini*.
  $slugs = @()
  foreach ($f in (Join-Path $CodexHomeDir 'models_cache.json'), (Join-Path $HOME '.codex\models_cache.json')) {
    if (Test-Path $f) {
      try { $slugs = @((Get-Content $f -Raw | ConvertFrom-Json).models | ForEach-Object { $_.slug }) } catch {}
      if ($slugs.Count) { break }
    }
  }
  function Ver($s) { if ($s -match 'gpt-(\d+(\.\d+)?)') { [double]$Matches[1] } else { 0 } }
  function Pick($re) { $slugs | Where-Object { $_ -match $re } | Sort-Object { Ver $_ } -Descending | Select-Object -First 1 }
  $Model = Pick 'luna'
  if (-not $Model) { $Model = Pick 'mini' }
  if (-not $Model) { $Model = 'gpt-5.4-mini' }
  Write-Host "   memory model: $Model (override with HINDSIGHT_MODEL)"
}

# 4. Server + UI launchers ---------------------------------------------------
Say "Writing server config ($Model, reasoning=$Reasoning)"
# Failover: every call tries the Codex model first, so the fallback only runs while it is
# rate-limited and memory goes back to the Codex model as soon as its quota resets.
# MAX_THINKING_TOKENS=0 turns off extended thinking in the claude CLI the fallback spawns.
$FallbackEnv = ''
if ($Fallback -ne 'none' -and (Has claude)) {
  $FallbackEnv = @"
`$env:HINDSIGHT_API_LLM_STRATEGY = '{"mode":"failover"}'
`$env:HINDSIGHT_API_LLM_1_PROVIDER = 'claude-code'
`$env:HINDSIGHT_API_LLM_1_MODEL = '$Fallback'
`$env:MAX_THINKING_TOKENS = '0'
"@
  Write-Host "   fallback model: $Fallback (Claude login, only while $Model is rate-limited)"
}
Write-Utf8 (Join-Path $HomeDir 'run-server.ps1') @"
`$env:HINDSIGHT_API_HOST = '127.0.0.1'
`$env:HINDSIGHT_API_PORT = '$Port'
`$env:HINDSIGHT_API_LLM_PROVIDER = 'openai-codex'
`$env:HINDSIGHT_API_LLM_MODEL = '$Model'
`$env:HINDSIGHT_API_LLM_REASONING_EFFORT = '$Reasoning'
`$env:CODEX_HOME = '$CodexHomeDir'
$FallbackEnv
`$env:PYTHONIOENCODING = 'utf-8'
& '$ServerExe' *>> '$LogDir\server.log'
"@

if ($Ui -eq '1') {
  Say 'Installing web UI (@vectorize-io/hindsight-control-plane)'
  npm install -g @vectorize-io/hindsight-control-plane | Out-Null
  $UiCmd = Join-Path (npm prefix -g).Trim() 'hindsight-control-plane.cmd'
  if (-not (Test-Path $UiCmd)) { Fail "hindsight-control-plane not found at $UiCmd" }
  Write-Utf8 (Join-Path $HomeDir 'run-ui.ps1') @"
& '$UiCmd' -H 127.0.0.1 -p $UiPort -a $ApiUrl *>> '$LogDir\ui.log'
"@
}

# 5. Auto-start (Scheduled Task at logon, restarts on failure) ---------------
function Register-Logon($name, $script, $port) {
  Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
  Stop-Port $port
  $action   = New-ScheduledTaskAction -Execute 'powershell.exe' `
                -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
  $trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
  Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
  Start-ScheduledTask -TaskName $name
}

Say 'Registering auto-start tasks'
Register-Logon $TaskServer (Join-Path $HomeDir 'run-server.ps1') $Port
if ($Ui -eq '1') { Register-Logon $TaskUi (Join-Path $HomeDir 'run-ui.ps1') $UiPort }

Say 'Waiting for the server (first start downloads local embedding models)'
$healthy = $false
for ($i = 0; $i -lt 180; $i++) {
  try { Invoke-RestMethod "$ApiUrl/health" -TimeoutSec 3 | Out-Null; $healthy = $true; break } catch { Start-Sleep 2 }
}
if (-not $healthy) { Fail "Server did not become healthy (an unavailable model $Model also stops it). Log: $LogDir\server.log" }

# 6. Agent integrations ------------------------------------------------------
$coding = @()
if ($Agents -contains 'claude-code' -and (Has claude)) { $coding += 'claude-code' }
if ($Agents -contains 'codex') { $coding += 'codex' }
if ($coding.Count -gt 0) {
  Say "Connecting: $($coding -join ' ')"
  Backup (Join-Path $HOME '.claude\settings.json'); Backup (Join-Path $HOME '.codex\config.toml'); Backup (Join-Path $HOME '.codex\hooks.json')
  npx -y @vectorize-io/hindsight-coding-agents install @coding --server self-hosted --api-url $ApiUrl
  if ($LASTEXITCODE -ne 0) { Fail 'hindsight-coding-agents install failed' }
}

# Pi loads the adapter through a Pi package rather than an absolute path in its
# settings.json, so a settings file kept in git stays portable across machines.
$pi = ($Agents -contains 'pi') -and (Has pi)
if ($pi) {
  Say 'Connecting: pi'
  # Stage the runtime (dist\pi.js) when no Claude Code / Codex install above did.
  if (-not (Test-Path (Join-Path $HomeDir 'coding-agents\dist\pi.js'))) {
    npx -y @vectorize-io/hindsight-coding-agents update
    if ($LASTEXITCODE -ne 0) { Fail 'hindsight-coding-agents update failed' }
  }
  pi install $PiPackage | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail "pi install $PiPackage failed" }
  Write-Host "   $PiPackage installed"
}

if ($coding.Count -gt 0 -or $pi) {
  Write-Utf8 (Join-Path $HomeDir 'coding-agent.json') (@{ serverMode = 'self-hosted'; apiUrl = $ApiUrl; bankId = $Bank } | ConvertTo-Json)
}

if ($Agents -contains 'hermes') {
  $hermesPy = Join-Path $HOME '.hermes\hermes-agent\.venv\Scripts\python.exe'
  if ((Has hermes) -and (Test-Path $hermesPy)) {
    Say 'Connecting: hermes'
    uv pip install --quiet --python $hermesPy 'hindsight-client>=0.6.1'
    $hcfgDir = Join-Path $HOME '.hermes\hindsight'
    New-Item -ItemType Directory -Force -Path $hcfgDir | Out-Null
    Backup (Join-Path $hcfgDir 'config.json'); Backup (Join-Path $HOME '.hermes\config.yaml')
    Write-Utf8 (Join-Path $hcfgDir 'config.json') (@{ mode = 'local_external'; api_url = $ApiUrl; bank_id = $Bank } | ConvertTo-Json)
    hermes config set memory.provider hindsight | Out-Null
  } else { Write-Host '   hermes not found — skipped' }
}

# 7. Smoke test --------------------------------------------------------------
Say "Smoke test: retain + recall through $Model"
$checkBank = "install-check-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$retainBody = @{ items = @(@{ content = 'Dana, the backend lead, said she always prefers PostgreSQL over MySQL for new services.' }); async = $false } | ConvertTo-Json -Depth 5
$recallBody = @{ query = 'Which database does Dana prefer?'; types = $null } | ConvertTo-Json
$recalled = $false
# The LLM decides what is worth remembering; retry the retain before failing.
for ($i = 0; $i -lt 3 -and -not $recalled; $i++) {
  try { Invoke-RestMethod -Method Post "$ApiUrl/v1/default/banks/$checkBank/memories" -ContentType 'application/json' -Body $retainBody | Out-Null }
  catch { Fail "Retain failed — login or model $Model not usable. Try another: `$env:HINDSIGHT_MODEL=<model>. Log: $LogDir\server.log" }
  $r = Invoke-RestMethod -Method Post "$ApiUrl/v1/default/banks/$checkBank/memories/recall" -ContentType 'application/json' -Body $recallBody
  if (($r | ConvertTo-Json -Depth 10) -match 'postgres') { $recalled = $true }
}
if (-not $recalled) { Fail "Recall did not return the stored fact. See $LogDir\server.log" }
try { Invoke-RestMethod -Method Delete "$ApiUrl/v1/default/banks/$checkBank" | Out-Null } catch {}

Say "Done. Server: $ApiUrl  bank: $Bank  model: $Model ($Reasoning)"
if ($FallbackEnv) { Write-Host "   Fallback: $Fallback while $Model is rate-limited" }
if ($Ui -eq '1') { Write-Host "   Web UI: http://127.0.0.1:$UiPort" }
Write-Host '   Start a NEW Claude Code / Codex / Pi session (and restart Hermes if it runs as a service).'
