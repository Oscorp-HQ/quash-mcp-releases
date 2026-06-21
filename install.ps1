#requires -version 5
<#
  Quash MCP installer for Windows (x64).

    irm https://raw.githubusercontent.com/Oscorp-HQ/quash-mcp-releases/main/install.ps1 | iex

  What it does:
    1. Downloads quash-mcp + quash-sidecar (Windows x64) into %USERPROFILE%\.quash.
    2. Downloads config + prompt templates + the Android Portal APK.
    3. Registers the MCP server in every supported client config it finds
       (Claude Code, Claude Desktop, Cursor).
    4. Primes the MCP server so the first connect doesn't hit the client timeout.

  PowerShell mirror of scripts/install.sh. Windows is Android-only; iOS tools are
  macOS-only and are not present in the Windows build.

  Env overrides:
    QUASH_VERSION       release tag (default: latest)
    QUASH_BACKEND_URL   backend base URL (default: prod)
    QUASH_API_TOKEN     pre-seed the auth token (optional)
    QUASH_RELEASES_REPO owner/repo of the releases repo (default below)
    QUASH_FORCE         "1" -> reinstall even if the version stamp matches
#>
$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 hardening (applies to every Invoke-WebRequest/RestMethod):
#  - SilentlyContinue progress: IWR renders a progress bar that makes large
#    downloads (the ~290 MB sidecar) up to ~10x slower in 5.1.
#  - UseBasicParsing: skip IWR's Internet Explorer DOM engine, which throws
#    "IE engine not available / first-launch not complete" on a fresh Windows.
$ProgressPreference = 'SilentlyContinue'
$PSDefaultParameterValues['Invoke-WebRequest:UseBasicParsing'] = $true
$PSDefaultParameterValues['Invoke-RestMethod:UseBasicParsing'] = $true

$REPO    = if ($env:QUASH_RELEASES_REPO) { $env:QUASH_RELEASES_REPO } else { "Oscorp-HQ/quash-mcp-releases" }
$PLAT    = "windows-x86_64"
$QHOME   = Join-Path $env:USERPROFILE ".quash"
$BIN     = Join-Path $QHOME "bin"
$SIDEDIR = Join-Path $QHOME "sidecar"
$BACKEND = if ($env:QUASH_BACKEND_URL) { $env:QUASH_BACKEND_URL } else { "https://zenith.quashbugs.com" }

function Info($msg) { Write-Host "[quash] $msg" }

# GitHub API needs TLS 1.2 on older PowerShell/.NET defaults.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- resolve version --------------------------------------------------------
$VERSION = $env:QUASH_VERSION
if (-not $VERSION) {
  $VERSION = (Invoke-RestMethod "https://api.github.com/repos/$REPO/releases/latest").tag_name
}
if (-not $VERSION) { throw "Could not resolve a release version. Set `$env:QUASH_VERSION." }
Info "Version: $VERSION"
$DL = "https://github.com/$REPO/releases/download/$VERSION"

$STAMP = Join-Path $QHOME ".installed-version"
$alreadyInstalled = ($env:QUASH_FORCE -ne "1") -and (Test-Path $STAMP) -and ((Get-Content $STAMP -Raw).Trim() -eq $VERSION)

if ($alreadyInstalled) {
  Info "$VERSION already installed (set QUASH_FORCE=1 to reinstall). Refreshing client config only."
} else {
  New-Item -ItemType Directory -Force -Path $BIN | Out-Null

  # 1) quash-mcp (onedir zip) -> %USERPROFILE%\.quash\bin\quash-mcp\quash-mcp.exe
  Info "Downloading quash-mcp ..."
  $mcpZip = Join-Path $QHOME "quash-mcp.zip"
  Invoke-WebRequest "$DL/quash-mcp-$PLAT.zip" -OutFile $mcpZip
  Remove-Item -Recurse -Force (Join-Path $BIN "quash-mcp") -ErrorAction SilentlyContinue
  Expand-Archive -Path $mcpZip -DestinationPath $BIN -Force
  Remove-Item $mcpZip

  # 2) quash-sidecar (onedir zip) -> ...\sidecar\quash-sidecar\quash-sidecar.exe
  Info "Downloading quash-sidecar ..."
  Remove-Item -Recurse -Force $SIDEDIR -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $SIDEDIR | Out-Null
  $sideZip = Join-Path $QHOME "sidecar.zip"
  Invoke-WebRequest "$DL/quash-sidecar-$PLAT.zip" -OutFile $sideZip
  Expand-Archive -Path $sideZip -DestinationPath $SIDEDIR -Force
  Remove-Item $sideZip

  # 3) config.yaml (first install only) + prompt templates (always refreshed)
  $cfgYaml = Join-Path $QHOME "config.yaml"
  if (-not (Test-Path $cfgYaml)) {
    try { Invoke-WebRequest "$DL/config.yaml" -OutFile $cfgYaml; Info "wrote default config.yaml" }
    catch { Info "config.yaml not on release -- engine will use its bundled default." }
  } else {
    Info "Keeping existing config.yaml (not overwritten)."
  }
  try {
    $cd = Join-Path $QHOME "config-data.tar.gz"
    Invoke-WebRequest "$DL/config-data.tar.gz" -OutFile $cd
    tar -xzf $cd -C $QHOME    # bsdtar ships with Windows 10 1803+
    Remove-Item $cd
  } catch { Info "prompt templates not fetched -- engine will use bundled defaults." }

  # 4) Portal APK (Android on-device component)
  try {
    New-Item -ItemType Directory -Force -Path (Join-Path $QHOME "portal") | Out-Null
    Invoke-WebRequest "$DL/mahoraga-portal.apk" -OutFile (Join-Path $QHOME "portal\mahoraga-portal.apk")
    try { Invoke-WebRequest "$DL/portal-version" -OutFile (Join-Path $QHOME "portal\portal-version") } catch {}
    Info "Portal APK downloaded"
  } catch { Info "Portal APK not fetched (optional)." }

  # 5) tiktoken BPE cache so the engine can tokenize offline
  try {
    $tk = Join-Path $QHOME "tiktoken_cache"
    New-Item -ItemType Directory -Force -Path $tk | Out-Null
    Invoke-WebRequest "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken" `
      -OutFile (Join-Path $tk "9b5ad71b2ce5302211f9c61530b329a4922fc6a4")
  } catch { Info "tokenizer cache skipped -- will download on first use." }

  Set-Content -Path $STAMP -Value $VERSION -NoNewline
}

$MCP_BIN     = Join-Path $BIN "quash-mcp\quash-mcp.exe"
$SIDECAR_BIN = Join-Path $SIDEDIR "quash-sidecar\quash-sidecar.exe"
if (-not (Test-Path $MCP_BIN))     { throw "quash-mcp.exe not found at $MCP_BIN after install" }
if (-not (Test-Path $SIDECAR_BIN)) { throw "quash-sidecar.exe not found at $SIDECAR_BIN after install" }

# 6) test-gen (optional onedir zip)
$TGCMD = $null
try {
  $tgZip = Join-Path $QHOME "test-gen.zip"
  Invoke-WebRequest "$DL/quash-test-gen-$PLAT.zip" -OutFile $tgZip
  $tgDir = Join-Path $QHOME "test-gen"
  Remove-Item -Recurse -Force $tgDir -ErrorAction SilentlyContinue
  Expand-Archive -Path $tgZip -DestinationPath $tgDir -Force
  Remove-Item $tgZip
  $tgExe = Join-Path $tgDir "quash-test-gen\quash-test-gen.exe"
  if (Test-Path $tgExe) { $TGCMD = $tgExe }
} catch { Info "test-gen setup skipped (optional): $_" }

# 7) Android SDK detection (so GUI clients can find adb)
$ANDROID = $env:ANDROID_HOME
if (-not $ANDROID) {
  $cand = Join-Path $env:LOCALAPPDATA "Android\Sdk"
  if (Test-Path (Join-Path $cand "platform-tools\adb.exe")) { $ANDROID = $cand }
}

# 8) Register in MCP clients
function Register-Quash([string]$cfgPath) {
  $dir = Split-Path -Parent $cfgPath
  if (-not (Test-Path $dir)) { Info "  $cfgPath -- client dir not found, skipping."; return }

  # Load existing config defensively: the file may be missing, empty, or invalid
  # JSON, and an existing "mcpServers" key may itself be null. Any of those would
  # otherwise crash the Add-Member below.
  $cfg = $null
  if (Test-Path $cfgPath) {
    $raw = Get-Content $cfgPath -Raw -ErrorAction SilentlyContinue
    if ($raw -and $raw.Trim()) {
      try { $cfg = $raw | ConvertFrom-Json } catch { Info "  $cfgPath -- invalid JSON, recreating."; $cfg = $null }
    }
  }
  if ($null -eq $cfg) { $cfg = [pscustomobject]@{} }

  # Ensure mcpServers exists AND is a non-null object.
  if (($cfg.PSObject.Properties.Name -notcontains "mcpServers") -or ($null -eq $cfg.mcpServers)) {
    $cfg | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) -Force
  }

  $env_ = [ordered]@{ QUASH_SIDECAR_CMD = $SIDECAR_BIN; QUASH_BACKEND_URL = $BACKEND }
  if ($env:QUASH_API_TOKEN) { $env_.QUASH_API_TOKEN = $env:QUASH_API_TOKEN }
  if ($TGCMD)   { $env_.QUASH_TEST_GEN_AGENT_CMD = $TGCMD }
  if ($ANDROID) { $env_.ANDROID_HOME = $ANDROID }
  $entry = [ordered]@{ type = "stdio"; command = $MCP_BIN; env = $env_ }
  $cfg.mcpServers | Add-Member -NotePropertyName quash -NotePropertyValue ([pscustomobject]$entry) -Force
  # Back up before rewriting: this round-trips the whole file through
  # ConvertTo-Json, and a client config (notably Claude Code's .claude.json) can
  # be large/deeply nested. -Depth 100 (PowerShell's max) avoids silent
  # truncation of deeper nodes into type-name strings; the .bak is recovery
  # insurance if the round-trip ever loses something.
  if (Test-Path $cfgPath) { Copy-Item $cfgPath "$cfgPath.quash-bak" -Force -ErrorAction SilentlyContinue }
  $cfg | ConvertTo-Json -Depth 100 | Set-Content -Path $cfgPath -Encoding UTF8
  Info "  updated $cfgPath"
}
Info "Registering MCP clients ..."
# Isolate each registration: one client's malformed config must not abort the
# rest of the install (notably the priming step below).
foreach ($cfgPath in @(
    (Join-Path $env:USERPROFILE ".claude.json"),                   # Claude Code
    (Join-Path $env:APPDATA "Claude\claude_desktop_config.json"),  # Claude Desktop
    (Join-Path $env:USERPROFILE ".cursor\mcp.json")                # Cursor
)) {
  try { Register-Quash $cfgPath } catch { Info "  could not register $cfgPath : $_" }
}

# 9) prime (so first connect doesn't hit the client's startup timeout)
Info "Priming MCP server ..."
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"install","version":"0"}}}'
$env:QUASH_SIDECAR_CMD = $SIDECAR_BIN
try { $init | & $MCP_BIN *> $null } catch {}

Write-Host ""
Info "Installed to $QHOME"
Write-Host ""
Write-Host "  Next steps:"
Write-Host "  1. Restart your AI client (Claude Code / Claude Desktop / Cursor)."
Write-Host "  2. Ask: 'Use Quash and run the auth tool' to sign in."
Write-Host "  3. Ask: 'Use Quash and run the build tool' to verify your setup."
Write-Host ""
Write-Host "  Note: unsigned binaries may trigger SmartScreen/Defender on first run."
Write-Host "  If blocked, click 'More info -> Run anyway', or add a Defender exclusion"
Write-Host "  for $QHOME."
