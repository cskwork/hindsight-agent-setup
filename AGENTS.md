# Instructions for AI agents

A user gave you this repository's URL because they want Hindsight shared memory on their machine.
Follow these steps. Speak to the user in their language, in plain words.

1. **Detect the OS.** macOS/Linux → `bootstrap.sh` / `install.sh`. Windows → `bootstrap.ps1` / `install.ps1`
   (Windows support is beta: tell the user so).
2. **Check prerequisites:** `uv`, `node` 18+, `npx`, `codex` CLI (plus `curl` on macOS/Linux).
   For each missing one, show the install command from README.md and stop until it is installed.
   The user also needs a ChatGPT plan that includes Codex; the memory server uses it instead of an API key.
3. **Look before changing anything.** Check which memory tools are already connected to the user's
   agents (Claude Code `~/.claude/settings.json` hooks and `claude mcp list`, Codex `~/.codex/config.toml`
   and `~/.codex/hooks.json`, Hermes `~/.hermes/config.yaml` `memory.provider`, Pi `pi list`). Tell the user:
   - an auto-start service will run the memory server (port 8888) and web UI (port 9999) at login,
   - Claude Code and Codex get Hindsight hooks + an MCP server, Hermes gets Hindsight as memory provider,
     Pi gets the `pi-hindsight-memory` package (Hindsight's official Pi adapter),
   - agent configs are backed up first, other memory tools are left in place unless they ask otherwise.
   Ask for confirmation and wait.
4. **ChatGPT login for the server (one time).** The server keeps its own login in `~/.hindsight/codex-home`
   so it never logs the user out of their own Codex. Check it:
   - macOS/Linux: `CODEX_HOME=~/.hindsight/codex-home codex login status`
   - Windows: `$env:CODEX_HOME="$HOME\.hindsight\codex-home"; codex login status; Remove-Item Env:CODEX_HOME`

   If it is not logged in, you cannot do it for them (it opens a browser). Ask the user to run the
   login command (the same line with `login` instead of `login status`). In Claude Code they can type
   it with a leading `!`. Wait until they confirm.
5. **Install.**
   - macOS/Linux: `curl -fsSL https://raw.githubusercontent.com/cskwork/hindsight-agent-setup/main/bootstrap.sh | bash`
   - Windows: `irm https://raw.githubusercontent.com/cskwork/hindsight-agent-setup/main/bootstrap.ps1 | iex`

   Allow up to 10 minutes: the first start downloads local embedding models.
   Options are environment variables (see README.md). The model is picked automatically from the
   user's plan; if the installer reports the model is unusable, list the `slug` values in
   `~/.codex/models_cache.json`, ask the user which to use, and re-run with `HINDSIGHT_MODEL=<slug>`.
6. **Verify.** The installer ends with its own retain + recall test and prints `Done.` If more than one
   agent is installed, also store a unique phrase with one agent and recall it from another, then delete
   the test memory in the web UI (http://127.0.0.1:9999) or tell the user where to do it.
7. **Report** in a few sentences: what was installed, where the web UI is, and that they must start new
   agent sessions to get the memory tools. On failure, show the last lines of `~/.hindsight/logs/server.log`
   and what remains.
