#!/usr/bin/env bash
# Disconnect agents and stop the Hindsight server. Memory data and the server login are kept.
set -uo pipefail
LABEL="io.vectorize.hindsight"

npx -y @vectorize-io/hindsight-coding-agents uninstall claude-code codex || true

if command -v hermes >/dev/null 2>&1; then
  hermes memory off >/dev/null || true
fi

case "$(uname -s)" in
  Darwin)
    for l in "$LABEL" "$LABEL-ui"; do
      launchctl bootout "gui/$(id -u)/$l" 2>/dev/null || true
      mv "$HOME/Library/LaunchAgents/$l.plist" "$HOME/.hindsight/$l.plist.disabled" 2>/dev/null || true
    done
    ;;
  Linux)
    systemctl --user disable --now hindsight.service hindsight-ui.service 2>/dev/null || true
    ;;
esac

echo "Stopped and disconnected. Data kept in ~/.pg0 and ~/.hindsight."
echo "To remove the server package too: uv tool uninstall hindsight-api"
