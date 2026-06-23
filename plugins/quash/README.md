# Quash plugin

Drive real Android & iOS mobile-app automation on a locally connected device from your
AI agent — run natural-language test tasks, generate test cases, manage apps & builds, and
pull back streamed runs & reports. Powered by the Quash (mahoraga) automation engine.

> **Prerequisite — install the Quash engine first.** This plugin only wires up the MCP
> server; the automation engine, on-device Portal, WebDriverAgent, and device tooling are
> installed by the Quash installer:
>
> ```sh
> # macOS
> curl -fsSL https://raw.githubusercontent.com/Oscorp-HQ/quash-mcp-releases/main/install.sh | sh
> ```
>
> The plugin launches `~/.quash/bin/quash-mcp` and the installed sidecar. macOS/Linux are
> supported here; on Windows, use the installer's auto-registration instead (the plugin's
> `${HOME}` paths are POSIX-oriented).

## Install

```text
/plugin marketplace add Oscorp-HQ/quash-mcp-releases
/plugin install quash@quashbugs
```

Then authenticate and connect a device:

```text
"Use Quash: run auth with mode google."   # or: auth with my token qsh_…
"Use Quash: connect, then setup_portal if needed."
"Run this on the device: open Settings and turn on Airplane mode."
```

## Tools

`about`, `auth`, `connect`, `configure`, `setup_portal`, `setup_simulator`, `setup_device`,
`execute`, `generate_test_cases`, `usage`, `list_apps`, `builds`, `install_build`, `runs`,
`test_cases`, `suites`.

See the [full setup guide](https://github.com/Oscorp-HQ/quash-mcp-releases#readme).