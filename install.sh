#!/usr/bin/env bash
# Quash MCP installer — run this once to set up the Quash automation engine.
#
#   curl -fsSL https://get.quash.ai/install.sh | sh
#
# What it does:
#   1. Detects OS + architecture.
#   2. Downloads quash-mcp and quash-sidecar to ~/.quash/bin/.
#   3. Auto-registers the MCP server in every supported client config it finds
#      (Claude Desktop, Cursor).
#
# Requirements:
#   - macOS 13+ (arm64 or x86_64) or Linux x86_64
#   - curl
#   - adb on PATH (for device automation)
set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────
QUASH_HOME="${QUASH_HOME:-$HOME/.quash}"
BIN_DIR="$QUASH_HOME/bin"
RELEASES_REPO="Abhinav-Sai-Quash/quash-mcp-releases"
BASE_URL="${QUASH_DOWNLOAD_BASE:-https://github.com/${RELEASES_REPO}/releases/download}"
VERSION="${QUASH_VERSION:-v0.1.0}"

# ── helpers ───────────────────────────────────────────────────────────────────
info()    { printf '\033[0;32m[quash]\033[0m %s\n' "$*"; }
warn()    { printf '\033[0;33m[quash]\033[0m %s\n' "$*"; }
error()   { printf '\033[0;31m[quash]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }
success() { printf '\033[0;36m[quash]\033[0m %s\n' "$*"; }

require_cmd() {
  command -v "$1" &>/dev/null || error "'$1' not found. Install it and retry."
}

# ── detect platform ───────────────────────────────────────────────────────────
detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)  arch="x86_64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) error "Unsupported architecture: $arch" ;;
  esac
  case "$os" in
    darwin) echo "darwin-${arch}" ;;
    linux)  echo "linux-${arch}" ;;
    *) error "Unsupported OS: $os" ;;
  esac
}

# ── download binary ───────────────────────────────────────────────────────────
download_binary() {
  local name="$1"
  local platform="$2"
  local dest="$3"
  local url

  # Asset naming: {name}-{platform}  e.g. quash-mcp-darwin-arm64
  url="${BASE_URL}/${VERSION}/${name}-${platform}"

  info "Downloading ${name} ..."
  if command -v curl &>/dev/null; then
    curl -fsSL --progress-bar -o "$dest" "$url" || error "Download failed: $url"
  elif command -v wget &>/dev/null; then
    wget -q --show-progress -O "$dest" "$url" || error "Download failed: $url"
  else
    error "Neither curl nor wget found."
  fi
  chmod +x "$dest"
}

# ── register MCP client ───────────────────────────────────────────────────────
# Writes / merges the quash entry into an MCP JSON config file.
register_mcp_config() {
  local config_path="$1"
  local dir
  dir="$(dirname "$config_path")"

  if [[ ! -d "$dir" ]]; then
    info "  $config_path — client dir not found, skipping."
    return
  fi

  local entry
  entry="$(cat <<JSON
{
  "command": "${BIN_DIR}/quash-mcp",
  "env": {
    "QUASH_SIDECAR_CMD": "${BIN_DIR}/quash-sidecar"
  }
}
JSON
)"

  if [[ ! -f "$config_path" ]]; then
    # Create a fresh config with just the quash entry.
    printf '{\n  "mcpServers": {\n    "quash": %s\n  }\n}\n' "$entry" > "$config_path"
    info "  Created $config_path"
    return
  fi

  # Merge: add / overwrite the "quash" key inside mcpServers.
  if command -v python3 &>/dev/null; then
    python3 - "$config_path" "$entry" <<'PY'
import json, sys
path = sys.argv[1]
new_entry = json.loads(sys.argv[2])
with open(path) as f:
    cfg = json.load(f)
cfg.setdefault("mcpServers", {})["quash"] = new_entry
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print(f"  Updated {path}")
PY
  else
    warn "  python3 not found — skipping config merge for $config_path."
    warn "  Manually add the quash server to the mcpServers section:"
    printf '    "quash": %s\n' "$entry"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  require_cmd curl

  PLATFORM="$(detect_platform)"
  info "Platform: $PLATFORM"

  # Create ~/.quash/bin
  mkdir -p "$BIN_DIR"

  # Download both binaries
  download_binary "quash-mcp"     "$PLATFORM" "$BIN_DIR/quash-mcp"
  download_binary "quash-sidecar" "$PLATFORM" "$BIN_DIR/quash-sidecar"

  # Register in known MCP clients
  info "Registering MCP clients ..."

  # Claude Desktop (macOS)
  register_mcp_config "$HOME/Library/Application Support/Claude/claude_desktop_config.json"

  # Claude Desktop (Linux)
  register_mcp_config "$HOME/.config/Claude/claude_desktop_config.json"

  # Cursor
  register_mcp_config "$HOME/.cursor/mcp.json"

  echo ""
  success "Quash MCP installed to $BIN_DIR"
  echo ""
  echo "  Next steps:"
  echo "  1. Restart your MCP client (Claude Desktop / Cursor)."
  echo "  2. Ask Claude: 'Use Quash and run the auth tool' to sign in."
  echo "  3. Ask Claude: 'Use Quash and run the build tool' to verify your setup."
  echo ""
  echo "  To update: run this script again (it overwrites existing binaries)."
  echo "  To uninstall: rm -rf $QUASH_HOME and remove the 'quash' entry from"
  echo "  your MCP client config."
  echo ""
}

main "$@"
