#!/bin/sh
# Quash MCP installer — end users run:
#   curl -fsSL https://raw.githubusercontent.com/Abhinav-Sai-Quash/quash-mcp-releases/main/install.sh | sh
#
# Installs three things to ~/.quash:
#   bin/quash-mcp        single-file MCP server binary
#   bin/quash-sidecar    single-file automation engine (execution + reports)
#   test-gen-venv/       Python venv with the test-gen agent (needs Python 3.11+)
# …then registers the `quash` server in your MCP client configs.
#
# Env overrides: QUASH_VERSION (default: latest), QUASH_BACKEND_URL (default: prod).
set -eu

REPO="Abhinav-Sai-Quash/quash-mcp-releases"
QUASH_HOME="${QUASH_HOME:-$HOME/.quash}"
BIN="$QUASH_HOME/bin"
VENV="$QUASH_HOME/test-gen-venv"
BACKEND_URL="${QUASH_BACKEND_URL:-https://zenith.quashbugs.com}"

say()  { printf '[quash] %s\n' "$*"; }
die()  { printf '[quash] ERROR: %s\n' "$*" >&2; exit 1; }

# ── 1. platform ──────────────────────────────────────────────────────────────
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS-$ARCH" in
  Darwin-arm64)  PLAT="darwin-arm64" ;;
  Darwin-x86_64) PLAT="darwin-x86_64" ;;
  Linux-x86_64)  PLAT="linux-x86_64" ;;
  *) die "unsupported platform: $OS-$ARCH" ;;
esac
say "Platform: $PLAT"

# ── 2. resolve version ───────────────────────────────────────────────────────
VERSION="${QUASH_VERSION:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$VERSION" ] || die "could not determine latest release tag (set QUASH_VERSION=vX.Y.Z)"
fi
say "Version: $VERSION"
DL="https://github.com/$REPO/releases/download/$VERSION"

mkdir -p "$BIN"
fetch() { curl -fSL --progress-bar "$1" -o "$2" || die "download failed: $1"; }

# ── 3. binaries (single-file) ────────────────────────────────────────────────
say "Downloading quash-mcp ..."
fetch "$DL/quash-mcp-$PLAT" "$BIN/quash-mcp"
say "Downloading quash-sidecar ..."
fetch "$DL/quash-sidecar-$PLAT" "$BIN/quash-sidecar"
chmod +x "$BIN/quash-mcp" "$BIN/quash-sidecar"

# config (best-effort — sidecar falls back to its bundled config if absent)
curl -fsSL "$DL/config.yaml" -o "$QUASH_HOME/config.yaml" 2>/dev/null || true
if curl -fsSL "$DL/config-data.tar.gz" -o "$QUASH_HOME/config-data.tar.gz" 2>/dev/null; then
  tar -xzf "$QUASH_HOME/config-data.tar.gz" -C "$QUASH_HOME" && rm -f "$QUASH_HOME/config-data.tar.gz"
fi

# ── 4. de-quarantine + ad-hoc sign (macOS) ───────────────────────────────────
# Downloaded files are quarantined; strip it so they launch. (Proper public
# distribution should ship Developer-ID-signed + NOTARIZED binaries instead.)
if [ "$OS" = "Darwin" ]; then
  xattr -dr com.apple.quarantine "$BIN/quash-mcp" "$BIN/quash-sidecar" 2>/dev/null || true
  command -v codesign >/dev/null 2>&1 && {
    codesign --force --sign - "$BIN/quash-mcp" 2>/dev/null || true
    codesign --force --sign - "$BIN/quash-sidecar" 2>/dev/null || true
  }
fi

# ── 5. test-gen venv (needs Python 3.11+) ────────────────────────────────────
TEST_GEN_CMD=""
PY="$(command -v python3 || true)"
PY_OK=0
if [ -n "$PY" ]; then
  "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' && PY_OK=1
fi
if [ "$PY_OK" = "1" ]; then
  say "Setting up test-gen (Python venv) ..."
  # Resolve the wheel asset's download URL via curl (NOT Python urllib — the
  # system Python.framework often ships without a CA bundle, so urllib's TLS
  # verify fails; curl uses the OS trust store and works). The wheel name
  # carries a version, so we discover the URL from the release API.
  WHEEL_URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$VERSION" \
    | sed -n 's/.*"browser_download_url": *"\([^"]*\.whl\)".*/\1/p' | head -1)"
  if [ -n "$WHEEL_URL" ]; then
    # Keep the wheel's REAL filename — pip parses {name}-{ver}-{py}-{abi}-{plat}
    # from it; a renamed file like 'test-gen.whl' is rejected as invalid.
    WHEEL_FILE="$QUASH_HOME/$(basename "$WHEEL_URL")"
    fetch "$WHEEL_URL" "$WHEEL_FILE"
    [ -d "$VENV" ] || "$PY" -m venv "$VENV"
    "$VENV/bin/pip" install -q --upgrade pip || say "  (pip self-upgrade skipped)"
    if "$VENV/bin/pip" install -q "$WHEEL_FILE"; then
      TEST_GEN_CMD="$VENV/bin/python -m test_gen_agent"
      say "test-gen ready."
    else
      say "WARN: test-gen install failed — test-case generation unavailable (execution still works)."
    fi
    rm -f "$WHEEL_FILE"
  else
    say "WARN: no test-gen wheel in this release — test-case generation will be unavailable."
  fi
else
  say "WARN: Python 3.11+ not found — skipping test-gen setup (execution still works)."
  say "      Install Python 3.11+ and re-run to enable test-case generation."
fi

# ── 6. register the MCP server in client configs ─────────────────────────────
say "Registering MCP clients ..."
register() {  # $1 = config file path
  cfg="$1"; dir="$(dirname "$cfg")"
  [ -d "$dir" ] || { printf '[quash]   %s — client dir not found, skipping.\n' "$cfg"; return; }
  MCP_BIN="$BIN/quash-mcp" SIDECAR="$BIN/quash-sidecar" TGCMD="$TEST_GEN_CMD" \
  BACKEND="$BACKEND_URL" CFG="$cfg" "$PY" - <<'PYEOF' 2>/dev/null || printf '[quash]   %s — could not update.\n' "$cfg"
import json, os, pathlib
cfg = pathlib.Path(os.environ["CFG"])
d = json.loads(cfg.read_text()) if cfg.exists() else {}
servers = d.setdefault("mcpServers", {})
env = {
    "QUASH_SIDECAR_CMD": os.environ["SIDECAR"],
    "QUASH_BACKEND_URL": os.environ["BACKEND"],
}
if os.environ.get("TGCMD"):
    env["QUASH_TEST_GEN_AGENT_CMD"] = os.environ["TGCMD"]
servers["quash"] = {"type": "stdio", "command": os.environ["MCP_BIN"], "env": env}
cfg.parent.mkdir(parents=True, exist_ok=True)
cfg.write_text(json.dumps(d, indent=2))
print(f"  Updated {cfg}")
PYEOF
}
# python3 is required to register; if absent we still installed the binaries.
if [ -n "$PY" ]; then
  register "$HOME/.claude.json"                                                       # Claude Code
  register "$HOME/Library/Application Support/Claude/claude_desktop_config.json"       # Claude Desktop (macOS)
  register "$HOME/.config/Claude/claude_desktop_config.json"                           # Claude Desktop (Linux)
  register "$HOME/.cursor/mcp.json"                                                    # Cursor
else
  say "WARN: python3 not found — installed binaries but could not auto-register MCP clients."
fi

cat <<EOF

[quash] Quash MCP installed to $BIN

  Next steps:
  1. Restart your MCP client (Claude Desktop / Cursor / Claude Code).
  2. Generate an MCP token in the Quash desktop app (Settings → MCP / API Token).
  3. Ask Claude: 'Use Quash and run the auth tool with my token' to sign in.
  4. Ask Claude: 'Use Quash and run the build tool' to verify your setup.

  Backend: $BACKEND_URL  (override with QUASH_BACKEND_URL)
  Update:  re-run this script.  Uninstall: rm -rf $QUASH_HOME and remove the
           'quash' entry from your MCP client config.
EOF
