# Quash MCP

The Quash MCP server lets an AI agent (Claude Code, Claude Desktop, Cursor, …)
drive real mobile-app automation on a connected device: run natural-language test
tasks, generate test cases from prompts/docs/repos, manage apps & builds, and pull
back streamed runs and reports — all powered by the Quash (mahoraga) automation
engine.

This guide covers installing it on **macOS or Windows**, wiring it into your
agent, generating an API token, preparing a device, and using every tool.

---

## Platform support

| Platform | Android | iOS (simulator + physical) | Installer |
|---|:---:|:---:|---|
| **macOS** (Apple Silicon) | ✅ | ✅ | `install.sh` (`curl … \| sh`) |
| **Windows** (x64) | ✅ | ❌ *(Apple toolchain is macOS-only)* | `install.ps1` (`irm … \| iex`) |

> iOS automation needs Xcode / WebDriverAgent / `devicectl` / `iproxy`, which exist
> only on macOS — so the iOS tools (`setup_simulator`, `setup_device`) appear in
> the macOS build only. Windows is Android-only. Linux x86_64 can be built from
> source but isn't published as a release binary.

---

## 1. Prerequisites

- **macOS 13+ (Apple Silicon)** or **Windows 10/11 (x64)**.
- **`adb`** on your `PATH` (Android platform-tools) for Android automation. On
  Windows the installer also detects `%LOCALAPPDATA%\Android\Sdk`.
- **A device:** an Android device/emulator (USB debugging on), or — on macOS — an
  iOS simulator or a physical iPhone (Developer Mode on, trusted, USB).
- **A Quash account** to authenticate (step 3 for a token, or browser sign-in in step 5).
- For iOS on macOS: **Xcode** installed (for the WebDriverAgent build).

> The installer also downloads the automation engine, a bundled test-generation
> component, and the on-device Android **Portal APK**.

---

## 2. Install

One command installs everything and auto-registers the server in every supported
agent config it finds (Claude Code, Claude Desktop, Cursor). Pick your platform:

**macOS**
```sh
curl -fsSL https://raw.githubusercontent.com/Oscorp-HQ/quash-mcp-releases/main/install.sh | sh
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/Oscorp-HQ/quash-mcp-releases/main/install.ps1 | iex
```

This installs the latest release into `~/.quash` (macOS) / `%USERPROFILE%\.quash`
(Windows) and **connects to Quash production automatically** — no backend URL to
configure.

> **Cursor users:** after running the installer above (needed for the engine), you can
> one-click add the MCP server to Cursor:
>
> [![Add Quash to Cursor](https://cursor.com/deeplink/mcp-install-dark.svg)](cursor://anysphere.cursor-deeplink/mcp/install?name=quash&config=eyJjb21tYW5kIjoiJHt1c2VySG9tZX0vLnF1YXNoL2Jpbi9xdWFzaC1tY3AiLCJlbnYiOnsiUVVBU0hfU0lERUNBUl9DTUQiOiIke3VzZXJIb21lfS8ucXVhc2gvc2lkZWNhci9xdWFzaC1zaWRlY2FyL3F1YXNoLXNpZGVjYXIiLCJRVUFTSF9URVNUX0dFTl9BR0VOVF9DTUQiOiIke3VzZXJIb21lfS8ucXVhc2gvdGVzdC1nZW4tdmVudi9iaW4vcHl0aG9uIC1tIHRlc3RfZ2VuX2FnZW50In19)
>
> (The installer already auto-registers Cursor, so this is only needed if you skipped that or removed the entry.)

### Options (env vars)

> **macOS gotcha:** environment variables must go on the piped **`sh`**, *not* on
> `curl` — a prefix on `curl` is ignored. On Windows, set `$env:…` before the `irm`.

**macOS — wire your token in / pin a version:**
```sh
# Token at install time (recommended — see step 3):
curl -fsSL https://raw.githubusercontent.com/Oscorp-HQ/quash-mcp-releases/main/install.sh | QUASH_API_TOKEN=qsh_xxxxxxxx sh

# Pin a specific version:
curl -fsSL https://raw.githubusercontent.com/Oscorp-HQ/quash-mcp-releases/main/install.sh | QUASH_VERSION=v1.1.0 sh
```

**Windows — same, via `$env:`:**
```powershell
$env:QUASH_API_TOKEN = "qsh_xxxxxxxx"
irm https://raw.githubusercontent.com/Oscorp-HQ/quash-mcp-releases/main/install.ps1 | iex
```

| Env var | Default | Purpose |
|---|---|---|
| `QUASH_API_TOKEN` | _(unset)_ | API token; if set, the MCP signs in automatically on startup |
| `QUASH_VERSION` | latest | Release tag to install |
| `QUASH_BACKEND_URL` | production | Override the backend (staging/local) |
| `QUASH_FORCE` | `0` | `1` forces a full reinstall even if the version matches |

Re-running the installer is safe: it refreshes config and, with `QUASH_FORCE=1`,
reinstalls the binaries. **Reconnecting the agent does not update the server —
only re-running the installer does.**

---

## 3. Generate an API token from the Quash app

The token lets the MCP authenticate without a browser. (Prefer not to manage a
token? Skip to step 5 and use **Google sign-in** instead.)

1. Open the **Quash desktop app** and sign in.
2. Go to **Settings → Integrations**.
3. Click **Generate token** (or regenerate to replace an existing one).
4. **Copy the token** — it starts with `qsh_`. It's shown once; store it safely.

Generating a new token **invalidates the previous one**, so update it everywhere
you use it. The token is scoped to the organization you're signed into and is
stored only in your agent's MCP config `env` block — never passed through the chat.

---

## 4. Add it to your agent

The installer auto-registers the `quash` server, so usually there's nothing to do.
To verify or add it manually, the entry looks like this — **use the paths for your
platform**:

**macOS**
```jsonc
{
  "mcpServers": {
    "quash": {
      "type": "stdio",
      "command": "/Users/<you>/.quash/bin/quash-mcp",
      "env": {
        "QUASH_SIDECAR_CMD": "/Users/<you>/.quash/sidecar/quash-sidecar/quash-sidecar",
        "QUASH_TEST_GEN_AGENT_CMD": "/Users/<you>/.quash/test-gen-venv/bin/python -m test_gen_agent",
        "QUASH_API_TOKEN": "qsh_xxxxxxxx"
      }
    }
  }
}
```

**Windows**
```jsonc
{
  "mcpServers": {
    "quash": {
      "type": "stdio",
      "command": "C:\\Users\\<you>\\.quash\\bin\\quash-mcp\\quash-mcp.exe",
      "env": {
        "QUASH_SIDECAR_CMD": "C:\\Users\\<you>\\.quash\\sidecar\\quash-sidecar\\quash-sidecar.exe",
        "QUASH_API_TOKEN": "qsh_xxxxxxxx",
        "ANDROID_HOME": "C:\\Users\\<you>\\AppData\\Local\\Android\\Sdk"
      }
    }
  }
}
```

Config file locations: Claude Code → `~/.claude.json` (macOS) /
`%USERPROFILE%\.claude.json` (Windows); Claude Desktop →
`~/Library/Application Support/Claude/claude_desktop_config.json` /
`%APPDATA%\Claude\claude_desktop_config.json`; Cursor → `~/.cursor/mcp.json` /
`%USERPROFILE%\.cursor\mcp.json`.

After editing config, **restart the agent** (or `/mcp` → reconnect in Claude Code).

### JetBrains IDEs (IntelliJ IDEA, PyCharm)

JetBrains AI Assistant supports MCP over stdio. After running the installer (step 2):

1. Open **Settings → Tools → AI Assistant → Model Context Protocol (MCP)**.
2. **Easiest:** click **Import from Claude** — since the installer already registered Quash
   in Claude Desktop, the `quash` server is pulled in automatically.
3. **Or add manually:** click **Add**, then paste this JSON (JetBrains does *not* expand
   environment variables, so use absolute paths — replace `<you>` with your username):

   **macOS**
   ```jsonc
   {
     "mcpServers": {
       "quash": {
         "command": "/Users/<you>/.quash/bin/quash-mcp",
         "env": {
           "QUASH_SIDECAR_CMD": "/Users/<you>/.quash/sidecar/quash-sidecar/quash-sidecar",
           "QUASH_TEST_GEN_AGENT_CMD": "/Users/<you>/.quash/test-gen-venv/bin/python -m test_gen_agent"
         }
       }
     }
   }
   ```
   **Windows**
   ```jsonc
   {
     "mcpServers": {
       "quash": {
         "command": "C:\\Users\\<you>\\.quash\\bin\\quash-mcp\\quash-mcp.exe",
         "env": {
           "QUASH_SIDECAR_CMD": "C:\\Users\\<you>\\.quash\\sidecar\\quash-sidecar\\quash-sidecar.exe",
           "QUASH_TEST_GEN_AGENT_CMD": "C:\\Users\\<you>\\.quash\\test-gen-venv\\Scripts\\python.exe -m test_gen_agent"
         }
       }
     }
   }
   ```
4. Click **OK → Apply** to start the server.

> **Android Studio:** its agent (Gemini Agent Mode) currently supports MCP over **HTTP/Streamable
> only**, not stdio, so the config above does not apply there yet.

---

## 5. Authenticate

- **If you set `QUASH_API_TOKEN`**, the server signs in automatically on startup.
- **Otherwise**, ask the agent to authenticate:
  - **Google (browser):** "Use Quash, run `auth` with mode `google`."
  - **Token:** "Use Quash, run `auth` with my token `qsh_…`."

Check status anytime with the `about` / `configure` tools.

---

## 6. Prepare the device

1. **Connect** — "Use Quash, `connect`." It detects the device (or lists them if
   several), warms the engine, and runs a setup health check.
2. **Finish setup for that device type:**
   - **Android** — if `connect` reports *"Portal not ready"*, run **`setup_portal`**:
     it installs the on-device Quash Portal app and enables its accessibility
     service (idempotent). If the device blocks it, it returns `manual_required`
     with the steps for **Settings → Accessibility**.
   - **iOS simulator (macOS)** — run **`setup_simulator`**: builds + launches
     WebDriverAgent for the booted simulator (no signing needed).
   - **iOS physical iPhone (macOS)** — run **`setup_device`**: resolves your Apple
     Developer **signing team** (set it with `configure signing_team=<TEAMID>`, or
     it's auto-detected from your keychain), builds + signs WebDriverAgent, starts
     the USB tunnel, and launches it. Requires Xcode, Developer Mode on, and the
     iPhone trusted over USB.

---

## 7. Using the tools

Ask the agent in plain language; it calls these tools:

| Tool | What it does | Platform |
|---|---|---|
| `about` | Server name, running version, latest release, update command | all |
| `auth` | Sign in (`google` browser flow, or `token`) | all |
| `connect` | Detect/select a device; health-check adb, Portal, engine, auth | all |
| `configure` | View/change execution + test-gen settings (model, temperature, max steps, vision, `signing_team`) | all |
| `setup_portal` | Install the Android Portal app + enable accessibility (idempotent) | all |
| `setup_simulator` | Build + launch WebDriverAgent for a booted iOS simulator | macOS |
| `setup_device` | Sign + launch WebDriverAgent on a physical iPhone over USB | macOS |
| `execute` | Run a natural-language test task on the device (streams progress) | all |
| `generate_test_cases` | Generate test cases from a prompt, local files, or a git repo | all |
| `usage` | Current plan, remaining minutes, feature limits | all |
| `list_apps` | List apps in your org | all |
| `builds` | List builds for an app (version, tag, installable) | all |
| `install_build` | Download a build's APK and install it on the device | all |
| `runs` | Browse recent runs, or fetch one run's full report + share link | all |
| `test_cases` / `suites` | Browse test cases and suites | all |

**Typical first session:**

```
"Use Quash: connect, then setup_portal if needed."          # Android
"Use Quash: connect, then setup_simulator."                 # iOS simulator (macOS)
"Run this on the device: open Settings and turn on Airplane mode."
"Show me the report for that run."
"Generate test cases for https://github.com/acme/my-app."
```

---

## 8. Updating

Re-run the installer for your platform (macOS `curl … | sh`, Windows `irm … | iex`),
then **restart the agent**. Confirm with the `about` tool — it reports the running
version and whether a newer release exists.

---

## 9. Troubleshooting

- **"Portal not ready" (Android)** → run `setup_portal`. If it returns
  `manual_required`, enable *Mahoraga Portal* under **Settings → Accessibility**.
- **adb / device not found** → install Android platform-tools, ensure `adb` is on
  `PATH` (Windows: set `ANDROID_HOME`), and that the device shows under `adb devices`.
- **iOS `setup_device` signing fails (macOS)** → set your team with
  `configure signing_team=<TEAMID>`, ensure your Apple ID is signed into
  **Xcode → Settings → Accounts** (with an *Apple Development* certificate in the
  keychain), and the iPhone is in Developer Mode + trusted.
- **Session expired / not authenticated** → re-run `auth`, or refresh
  `QUASH_API_TOKEN` (generating a new token invalidates the old one).
- **A run isn't visible in the app** → the run's org must match the app's org;
  check the `execute` result's `warning` field.
- **macOS Gatekeeper warning** → public binaries are ad-hoc signed; if blocked,
  allow them under **System Settings → Privacy & Security**.
- **Windows SmartScreen / Defender** → unsigned binaries may prompt *"Windows
  protected your PC"*; click **More info → Run anyway**, or add a Defender
  exclusion for `%USERPROFILE%\.quash`.
