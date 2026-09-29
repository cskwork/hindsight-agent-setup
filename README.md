# hindsight-agent-setup

**One shared long-term memory for Claude Code, Codex and Hermes** — powered by
[Hindsight](https://github.com/vectorize-io/hindsight). No Docker, no API key: memory is processed
with your ChatGPT plan through Codex. macOS and Windows (beta), Linux too.

Claude Code·Codex·Hermes가 하나의 장기 기억을 함께 쓰게 해 줍니다. Docker와 API 키 없이 ChatGPT 구독만 사용합니다.

🌐 Landing page: https://cskwork.github.io/hindsight-agent-setup/

> Unofficial community installer. Hindsight is made by [Vectorize](https://vectorize.io); this repo only
> wires it up.

## Quick start: let your agent do it

Paste this into Claude Code, Codex or Hermes:

```text
Set up shared memory for my coding agents: https://github.com/cskwork/hindsight-agent-setup
```

The agent reads [AGENTS.md](AGENTS.md), checks your machine, asks before changing anything,
and verifies the result. You will be asked to log in to ChatGPT once in the browser.

## Or run it yourself

Requirements: [`uv`](https://docs.astral.sh/uv/), Node.js 18+, [Codex CLI](https://github.com/openai/codex)
(`npm i -g @openai/codex`), and a ChatGPT plan that includes Codex.

**macOS / Linux**

```bash
CODEX_HOME=~/.hindsight/codex-home codex login      # one time: separate login for the memory server
curl -fsSL https://raw.githubusercontent.com/cskwork/hindsight-agent-setup/main/bootstrap.sh | bash
```

**Windows (PowerShell, x64, beta)**

```powershell
$env:CODEX_HOME="$HOME\.hindsight\codex-home"; codex login; Remove-Item Env:CODEX_HOME   # one time
irm https://raw.githubusercontent.com/cskwork/hindsight-agent-setup/main/bootstrap.ps1 | iex
```

Then start new agent sessions. Open the memory web UI at http://127.0.0.1:9999.

## What gets installed

| Part | Setup |
|------|-------|
| Memory server | `hindsight-api` via `uv`, on `127.0.0.1:8888`, embedded PostgreSQL in `~/.pg0` |
| Web UI | `@vectorize-io/hindsight-control-plane` on `127.0.0.1:9999` |
| Auto-start | At login, restarted if it stops: launchd (macOS), Scheduled Task (Windows), systemd `--user` (Linux) |
| Memory model | Your ChatGPT plan via the `openai-codex` provider. Picks the cheapest available (newest `*-luna`, else `*-mini`), reasoning `low` |
| Login | A separate Codex login in `~/.hindsight/codex-home`, so the server's token refresh never logs you out of your own Codex |
| Claude Code, Codex | Official [`@vectorize-io/hindsight-coding-agents`](https://www.npmjs.com/package/@vectorize-io/hindsight-coding-agents) hooks + MCP server |
| Hermes | Built-in Hindsight memory provider (`local_external` mode); skipped if Hermes is not installed |
| Memory bank | Every agent shares one bank, `agents` |

Your conversations are sent to OpenAI (through your ChatGPT plan) to be turned into memories.
Everything else stays on your machine.

## Options

Set as environment variables before running the installer (`HINDSIGHT_MODEL=gpt-5.4-mini ./install.sh`).

| Variable | Default | Notes |
|----------|---------|-------|
| `HINDSIGHT_MODEL` | auto | Any `slug` in `~/.codex/models_cache.json` |
| `HINDSIGHT_REASONING` | `low` | `low`, `medium`, `high`, `xhigh`. Higher = better memory consolidation, more plan usage |
| `HINDSIGHT_BANK` | `agents` | Shared memory bank name |
| `HINDSIGHT_AGENTS` | `claude-code codex hermes` | Which agents to connect |
| `HINDSIGHT_UI` | `1` | `0` = no web UI |
| `HINDSIGHT_PORT` / `HINDSIGHT_UI_PORT` | `8888` / `9999` | |

The installer is idempotent (safe to re-run) and ends with a real store + recall test through the chosen model.

## Operate

| Task | macOS / Linux | Windows |
|------|---------------|---------|
| Status | `curl http://127.0.0.1:8888/health` | `irm http://127.0.0.1:8888/health` |
| Logs | `~/.hindsight/logs/server.log` | `~\.hindsight\logs\server.log` |
| Restart | `launchctl kickstart -k gui/$(id -u)/io.vectorize.hindsight` | `Stop-ScheduledTask 'Hindsight Server'; Start-ScheduledTask 'Hindsight Server'` |
| Memory stopped saving | Login expired: re-run the one-time login command above | same |
| Uninstall (keeps data) | `~/.hindsight/setup/uninstall.sh` | `~\.hindsight\setup\uninstall.ps1` |

Agent configs are backed up as `*.bak-hindsight-<timestamp>` before every change.

## License

MIT
