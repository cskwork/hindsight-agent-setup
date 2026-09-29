#!/usr/bin/env bash
# One-line install (macOS / Linux):
#   curl -fsSL https://raw.githubusercontent.com/cskwork/hindsight-agent-setup/main/bootstrap.sh | bash
# Downloads the latest scripts into ~/.hindsight/setup and runs install.sh. No git needed.
set -euo pipefail
REPO="cskwork/hindsight-agent-setup"
DEST="$HOME/.hindsight/setup"

mkdir -p "$DEST"
curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" | tar xz -C "$DEST" --strip-components 1
chmod +x "$DEST"/*.sh
exec "$DEST/install.sh" "$@"
