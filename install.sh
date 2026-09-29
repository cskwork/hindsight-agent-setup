#!/usr/bin/env bash
# Hindsight shared memory for Claude Code, Codex and Hermes — no Docker.
# Idempotent: safe to re-run. macOS (launchd) and Linux (systemd --user).
set -euo pipefail

MODEL="${HINDSIGHT_MODEL:-}"                    # empty = cheapest Codex model on your plan (luna > mini)
REASONING="${HINDSIGHT_REASONING:-low}"         # low | medium | high | xhigh
FALLBACK="${HINDSIGHT_FALLBACK_MODEL:-claude-haiku-4-5}"  # used via your Claude login while the Codex model is rate-limited; none = off
BANK="${HINDSIGHT_BANK:-agents}"                # one bank shared by every agent
PORT="${HINDSIGHT_PORT:-8888}"
UI_PORT="${HINDSIGHT_UI_PORT:-9999}"
UI="${HINDSIGHT_UI:-1}"                          # 1 = also run the web UI at login
AGENTS="${HINDSIGHT_AGENTS:-claude-code codex hermes}"

HOME_DIR="$HOME/.hindsight"
CODEX_HOME_DIR="$HOME_DIR/codex-home"            # separate ChatGPT login so token refreshes never log out your own Codex
API_URL="http://127.0.0.1:$PORT"
LABEL="io.vectorize.hindsight"

say()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }
backup() { [ -e "$1" ] && cp "$1" "$1.bak-hindsight-$(date +%Y%m%d%H%M%S)" || true; }

# 1. Prerequisites -----------------------------------------------------------
say "Checking prerequisites"
has uv    || fail "uv is required: curl -LsSf https://astral.sh/uv/install.sh | sh"
has node  || fail "node (>=18) is required for the Claude Code / Codex integration"
has npx   || fail "npx is required"
has codex || fail "codex CLI is required for the ChatGPT login: npm i -g @openai/codex"
has curl  || fail "curl is required"

# 2. Server install ----------------------------------------------------------
say "Installing hindsight-api (uv tool)"
uv tool install --upgrade hindsight-api >/dev/null
SERVER_BIN="$(uv tool dir --bin)/hindsight-api"
[ -x "$SERVER_BIN" ] || fail "hindsight-api not found at $SERVER_BIN"

mkdir -p "$HOME_DIR/logs" "$CODEX_HOME_DIR"
chmod 700 "$CODEX_HOME_DIR"

# 3. Dedicated ChatGPT login for the server ----------------------------------
if ! CODEX_HOME="$CODEX_HOME_DIR" codex login status >/dev/null 2>&1; then
  say "The memory server needs its own ChatGPT login (one time)"
  if ( : </dev/tty ) 2>/dev/null; then          # works under `curl | bash` too
    CODEX_HOME="$CODEX_HOME_DIR" codex login </dev/tty
  else
    fail "No terminal. Run this yourself, then re-run install.sh:  CODEX_HOME=$CODEX_HOME_DIR codex login"
  fi
fi

if [ -z "$MODEL" ]; then
  # Codex keeps the plan's model list in models_cache.json; prefer the newest *luna*, then *mini*.
  MODEL="$(node -e '
    const fs = require("fs");
    let slugs = [];
    for (const f of process.argv.slice(1)) {
      try { slugs = JSON.parse(fs.readFileSync(f, "utf8")).models.map(m => m.slug); if (slugs.length) break; } catch {}
    }
    const ver = s => parseFloat((s.match(/gpt-(\d+(?:\.\d+)?)/) || [0, 0])[1]);
    const pick = re => slugs.filter(s => re.test(s)).sort((a, b) => ver(b) - ver(a))[0];
    console.log(pick(/luna/) || pick(/mini/) || "gpt-5.4-mini");
  ' "$CODEX_HOME_DIR/models_cache.json" "$HOME/.codex/models_cache.json")"
  echo "   memory model: $MODEL (override with HINDSIGHT_MODEL)"
fi

# 4. Server config + launcher ------------------------------------------------
say "Writing server config ($MODEL, reasoning=$REASONING)"
cat > "$HOME_DIR/server.env" <<EOF
HINDSIGHT_API_HOST=127.0.0.1
HINDSIGHT_API_PORT=$PORT
HINDSIGHT_API_LLM_PROVIDER=openai-codex
HINDSIGHT_API_LLM_MODEL=$MODEL
HINDSIGHT_API_LLM_REASONING_EFFORT=$REASONING
CODEX_HOME=$CODEX_HOME_DIR
EOF

# Failover: every call tries the Codex model first, so the fallback only runs while it is
# rate-limited and memory goes back to the Codex model as soon as its quota resets.
if [ "$FALLBACK" != none ] && has claude; then
  cat >> "$HOME_DIR/server.env" <<EOF
HINDSIGHT_API_LLM_STRATEGY='{"mode":"failover"}'
HINDSIGHT_API_LLM_1_PROVIDER=claude-code
HINDSIGHT_API_LLM_1_MODEL=$FALLBACK
EOF
  echo "   fallback model: $FALLBACK (Claude login, only while $MODEL is rate-limited)"
fi

cat > "$HOME_DIR/run-server.sh" <<EOF
#!/usr/bin/env bash
set -a; . "$HOME_DIR/server.env"; set +a
exec "$SERVER_BIN"
EOF
chmod +x "$HOME_DIR/run-server.sh"

if [ "$UI" = 1 ]; then
  say "Installing web UI (@vectorize-io/hindsight-control-plane)"
  npm install -g @vectorize-io/hindsight-control-plane >/dev/null 2>&1 || fail "npm install -g @vectorize-io/hindsight-control-plane failed"
  UI_BIN="$(npm prefix -g)/bin/hindsight-control-plane"
  [ -x "$UI_BIN" ] || fail "hindsight-control-plane not found at $UI_BIN"
  cat > "$HOME_DIR/run-ui.sh" <<EOF
#!/usr/bin/env bash
export PATH="$(dirname "$(command -v node)"):\$PATH"
exec "$UI_BIN" -H 127.0.0.1 -p $UI_PORT -a $API_URL
EOF
  chmod +x "$HOME_DIR/run-ui.sh"
fi

# 5. Auto-start services -----------------------------------------------------
# register <label> <script> <log>
register() {
  case "$(uname -s)" in
    Darwin)
      local plist="$HOME/Library/LaunchAgents/$1.plist"
      cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array><string>$2</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$3</string>
  <key>StandardErrorPath</key><string>$3</string>
</dict></plist>
EOF
      launchctl bootout "gui/$(id -u)/$1" 2>/dev/null || true
      # bootout is asynchronous; bootstrapping before it finishes fails with an I/O error
      for _ in $(seq 1 20); do
        launchctl print "gui/$(id -u)/$1" >/dev/null 2>&1 || break
        sleep 0.5
      done
      launchctl bootstrap "gui/$(id -u)" "$plist" || fail "launchctl bootstrap failed for $1"
      ;;
    Linux)
      local unit_dir="$HOME/.config/systemd/user" name="${1##*.}.service"
      mkdir -p "$unit_dir"
      cat > "$unit_dir/$name" <<EOF
[Unit]
Description=$1
[Service]
ExecStart=$2
Restart=always
StandardOutput=append:$3
StandardError=append:$3
[Install]
WantedBy=default.target
EOF
      systemctl --user daemon-reload
      systemctl --user enable "$name" >/dev/null
      systemctl --user restart "$name"
      ;;
    *) fail "Unsupported OS: $(uname -s) (Windows: use install.ps1)" ;;
  esac
}

say "Registering auto-start services"
register "$LABEL" "$HOME_DIR/run-server.sh" "$HOME_DIR/logs/server.log"
[ "$UI" = 1 ] && register "$LABEL-ui" "$HOME_DIR/run-ui.sh" "$HOME_DIR/logs/ui.log"

say "Waiting for the server (first start downloads local embedding models)"
for _ in $(seq 1 180); do
  curl -sf "$API_URL/health" >/dev/null 2>&1 && break
  sleep 2
done
curl -sf "$API_URL/health" >/dev/null || fail "Server did not become healthy (an unavailable model $MODEL also stops it). Log: $HOME_DIR/logs/server.log"

# 6. Agent integrations ------------------------------------------------------
CODING=""
for a in $AGENTS; do
  case "$a" in
    claude-code) has claude && CODING="$CODING claude-code" ;;
    codex)       CODING="$CODING codex" ;;
  esac
done

if [ -n "$CODING" ]; then
  say "Connecting:$CODING"
  backup "$HOME/.claude/settings.json"; backup "$HOME/.codex/config.toml"; backup "$HOME/.codex/hooks.json"
  # shellcheck disable=SC2086
  npx -y @vectorize-io/hindsight-coding-agents install $CODING --server self-hosted --api-url "$API_URL"
  cat > "$HOME_DIR/coding-agent.json" <<EOF
{
  "serverMode": "self-hosted",
  "apiUrl": "$API_URL",
  "bankId": "$BANK"
}
EOF
fi

case " $AGENTS " in *" hermes "*)
  if has hermes && [ -x "$HOME/.hermes/hermes-agent/.venv/bin/python" ]; then
    say "Connecting: hermes"
    uv pip install --quiet --python "$HOME/.hermes/hermes-agent/.venv/bin/python" "hindsight-client>=0.6.1"
    mkdir -p "$HOME/.hermes/hindsight"
    backup "$HOME/.hermes/hindsight/config.json"; backup "$HOME/.hermes/config.yaml"
    cat > "$HOME/.hermes/hindsight/config.json" <<EOF
{
  "mode": "local_external",
  "api_url": "$API_URL",
  "bank_id": "$BANK"
}
EOF
    hermes config set memory.provider hindsight >/dev/null
  else
    echo "   hermes not found — skipped"
  fi
;; esac

# 7. Smoke test --------------------------------------------------------------
CHECK_BANK="install-check-$(date +%s)"
say "Smoke test: retain + recall through $MODEL"
# The LLM decides what is worth remembering; a realistic preference is extracted reliably,
# an obviously synthetic sentence is sometimes skipped. Retry the retain before failing.
recalled=0
for _ in 1 2 3; do
  curl -sf -X POST "$API_URL/v1/default/banks/$CHECK_BANK/memories" \
    -H 'Content-Type: application/json' \
    -d '{"items":[{"content":"Dana, the backend lead, said she always prefers PostgreSQL over MySQL for new services."}],"async":false}' >/dev/null \
    || fail "Retain failed — login or model $MODEL not usable. Try another: HINDSIGHT_MODEL=<model> ./install.sh. Log: $HOME_DIR/logs/server.log"
  if curl -sf -X POST "$API_URL/v1/default/banks/$CHECK_BANK/memories/recall" \
       -H 'Content-Type: application/json' -d '{"query":"Which database does Dana prefer?","types":null}' | grep -qi postgres; then
    recalled=1; break
  fi
done
[ "$recalled" = 1 ] || fail "Recall did not return the stored fact. See $HOME_DIR/logs/server.log"
curl -sf -X DELETE "$API_URL/v1/default/banks/$CHECK_BANK" >/dev/null || true

say "Done. Server: $API_URL  bank: $BANK  model: $MODEL ($REASONING)"
grep -q LLM_1_MODEL "$HOME_DIR/server.env" && echo "   Fallback: $FALLBACK while $MODEL is rate-limited"
[ "$UI" = 1 ] && echo "   Web UI: http://127.0.0.1:$UI_PORT"
echo "   Start a NEW Claude Code / Codex session (and restart the Hermes gateway if it runs as a service)."
