# Disconnect agents and stop the Hindsight server on Windows. Memory data and the server login are kept.
$ErrorActionPreference = 'Continue'

npx -y @vectorize-io/hindsight-coding-agents uninstall claude-code codex

if (Get-Command hermes -ErrorAction SilentlyContinue) { hermes memory off | Out-Null }

foreach ($name in 'Hindsight Server', 'Hindsight UI') {
  Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
}
foreach ($p in 8888, 9999) {
  Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
}

Write-Host 'Stopped and disconnected. Data kept in ~\.pg0 and ~\.hindsight.'
Write-Host 'To remove the server package too: uv tool uninstall hindsight-api'
