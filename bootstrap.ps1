# One-line install (Windows PowerShell):
#   irm https://raw.githubusercontent.com/cskwork/hindsight-agent-setup/main/bootstrap.ps1 | iex
# Downloads the latest scripts into ~\.hindsight\setup and runs install.ps1. No git needed.
$ErrorActionPreference = 'Stop'
$repo = 'cskwork/hindsight-agent-setup'
$dest = Join-Path $HOME '.hindsight\setup'
$zip  = Join-Path $env:TEMP 'hindsight-agent-setup.zip'
$tmp  = Join-Path $env:TEMP 'hindsight-agent-setup'

Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive $zip -DestinationPath $tmp -Force
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $tmp 'hindsight-agent-setup-main\*') $dest -Recurse -Force
Remove-Item $zip, $tmp -Recurse -Force

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'install.ps1')
