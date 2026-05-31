# openclaw-docker-chromium-vnc

A self-hosted [OpenClaw](https://github.com/openclaw/openclaw) agent deployment, containerized with Docker and wired to **local LM Studio models** over the LAN. The image adds a real Chromium browser for the agent's browser tool and exposes its virtual display through a password-protected [noVNC](https://novnc.com/) web client.

## What's in the box

- **Dockerized gateway** — builds on `ghcr.io/openclaw/openclaw:latest` and runs `openclaw gateway`.
- **Local LLMs** — the agent talks to an OpenAI-compatible LM Studio endpoint on the LAN. No cloud API, no per-token cost.
- **In-container browser tool** — Chromium is installed into the container so the agent can render JS pages, capture screenshots/PDFs, and take ARIA snapshots, all isolated from the host.
- **noVNC viewer** — watch the headed browser live in your web browser, password-gated.

## Repository layout

| Path | Purpose |
|---|---|
| `Dockerfile` | Extends the OpenClaw image; installs Chromium, fonts, Xvfb, x11vnc, noVNC/websockify. |
| `docker-compose.yml` | Service definition, ports, volume mounts, env. |
| `with-novnc.sh` | Entrypoint: starts Xvfb + a password-protected VNC server + noVNC bridge, then hands off to the OpenClaw gateway. |
| `.env.example` | Template for required secrets (copy to `.env`). |
| `agent/config/` | Runtime config, credentials, memory, and workspace state. **Gitignored** — lives only on the host. |
| `agent/config/openclaw.json` | Central agent config (gateway, models, browser, tools, channels) written by `openclaw configure`. Note `gateway.controlUi.allowedOrigins` must match `AGENT_PORT`. |

## Prerequisites

- Docker + Docker Compose.
- An [LM Studio](https://lmstudio.ai/) server (or any OpenAI-compatible endpoint) reachable from the container, with your models loaded and the server started.

## Quick start

```bash
# 1. Set a VNC password (the entrypoint refuses to start without one)
cp .env.example .env
$EDITOR .env            # set VNC_PASSWORD to a real value

# 2. Build the image and start the agent
docker compose up -d --build

# 3. Configure the agent (models, tools) on first run
docker compose exec openclaw-agent openclaw configure
docker compose up -d --force-recreate
```

The agent's config and state are persisted to `./agent/config` on the host via a volume mount, so they survive rebuilds.

## Ports

| Host | Container | Use | `.env` var |
|---|---|---|---|
| `18790` | `18789` | OpenClaw gateway / control UI | `AGENT_PORT` |
| `127.0.0.1:6080` | `6080` | noVNC web client (localhost-only) | `VNC_PORT` |

Open the control UI at `http://localhost:18790` and the browser viewer at `http://localhost:6080/vnc.html`.

The host ports default to the values above; override `AGENT_PORT` / `VNC_PORT` in `.env` (or inline) to avoid clashes — required when running more than one stack. See [Running multiple instances](#running-multiple-instances).

> **Important:** if you change `AGENT_PORT`, also update `gateway.controlUi.allowedOrigins` in `agent/config/openclaw.json` to list the new port. The gateway validates the browser's `Origin` header against that list, so a control UI loaded from `http://localhost:<new-port>` is rejected until its origin is added.

> **Note:** the noVNC client is served at `/vnc.html` — the bare root (`http://localhost:6080/`) only shows a directory listing, since the Debian `novnc` package ships no `index.html`. Click *Connect* and enter your `VNC_PASSWORD`.

## LM Studio integration

Point OpenClaw at your LM Studio server as a custom OpenAI-compatible provider. The `baseUrl` must use the machine's **LAN IP** (not `localhost`), since the agent runs inside a container. `apiKey` is unused by LM Studio but the field is required.

> **From experience:** editing the model list directly in `openclaw.json` doesn't always take effect. If your models don't show up, add them through `openclaw configure` instead (`docker compose exec openclaw-agent openclaw configure`) — it writes the same config but reliably picks up the changes.

From `agent/config/openclaw.json`:

```jsonc
{
  "models": {
    "mode": "merge",
    "providers": {
      "custom-192-168-1-111-1234": {
        "api": "openai-completions",
        "apiKey": "not-used",
        "baseUrl": "http://192.168.1.111:1234/v1",
        "models": [
          {
            "id": "google/gemma-4-26b-a4b",
            "name": "google/gemma-4-26b-a4b (Custom Provider)",
            "contextWindow": 128000,
            "maxTokens": 4096,
            "input": ["text", "image"],   // vision-capable
            "reasoning": false
          },
          {
            "id": "nvidia/nemotron-3-nano",
            "name": "nvidia/nemotron-3-nano (Custom Provider)",
            "contextWindow": 524288,
            "maxTokens": 16384,
            "input": ["text"],
            "reasoning": true
          }
        ]
      }
    }
  }
}
```

Select which model the agent uses by default:

```jsonc
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "custom-192-168-1-111-1234/google/gemma-4-26b-a4b"
      }
    }
  }
}
```

> **Tip:** route screenshot/image work to a vision-capable model (here, `gemma-4-26b`); use the text-only `nemotron-3-nano` for plain reasoning.

> **Note:** local models can be slow to first token, so the compose file sets `OPENCLAW_LLM_TIMEOUT=600000` (10 minutes) to keep requests from timing out mid-generation. Lower it if you'd rather fail fast.

## In-container browser (Chrome + VNC)

The OpenClaw image ships the browser *plugin* but no browser binary, so the `Dockerfile` installs Chromium plus a virtual display stack (`Xvfb`, `x11vnc`, `novnc`/`websockify`). Keeping the browser inside the container means it stays isolated from the host and reachable only through the password-gated noVNC bridge.

Enable the browser tool and wire it to the installed Chromium in `agent/config/openclaw.json`:

```jsonc
{
  "browser": {
    "enabled": true,
    "defaultProfile": "openclaw",
    "headless": false,              // headed, so you can watch it over VNC
    "executablePath": "/usr/bin/chromium",
    "noSandbox": true               // OK in an isolated, LAN-blocked container
  },
  "tools": {
    "profile": "coding",
    "alsoAllow": ["browser"]        // allow the browser tool on top of the profile
  }
}
```

The `with-novnc.sh` entrypoint launches a virtual X display, a VNC server bound to container-localhost, and the noVNC web bridge before starting the gateway — so the headed Chromium renders onto a display you can watch at `http://localhost:6080/vnc.html`.

Drive the browser tool manually:

```bash
docker compose exec openclaw-agent openclaw browser --browser-profile openclaw start
docker compose exec openclaw-agent openclaw browser --browser-profile openclaw open https://example.com
docker compose exec openclaw-agent openclaw browser --browser-profile openclaw snapshot
```

## Security

- `VNC_PASSWORD` is **required**; the entrypoint exits rather than expose an unauthenticated VNC server. The VNC server binds to container-localhost only, and noVNC is the sole bridge.
- The noVNC port is published to `127.0.0.1` only, so it isn't reachable from the LAN.
- `noSandbox: true` is acceptable here because the container is isolated and OpenClaw's SSRF guard blocks the **browser tool** from fetching private/LAN addresses. (This guard applies to the agent's browser/HTTP fetches, not the LLM provider connection — that's why the LM Studio `baseUrl` can still point at a LAN IP.) To restore the Chromium sandbox, add `chromium-sandbox` to the `Dockerfile` and drop the flag.
- Secrets live in `.env` and `agent/config/` — both gitignored. Never commit gateway tokens or VNC passwords.

## Common commands

```bash
docker compose up -d --build                 # rebuild image and recreate
docker compose logs -f openclaw-agent        # follow logs
docker compose exec openclaw-agent openclaw configure   # reconfigure
```

## Running multiple instances

The compose file has no fixed `container_name`, so each instance is distinguished by a Compose **project name** (`-p`). Give every instance its own host ports *and* state dirs, then run all its commands with the same `-p`:

```bash
# instance B: different ports and its own config/workspace
AGENT_PORT=18791 VNC_PORT=6081 \
CONFIG_DIR=./agent/inst-b/config WORKSPACE_DIR=./agent/inst-b/workspace \
docker compose -p inst-b up -d

docker compose -p inst-b exec openclaw-agent openclaw configure
docker compose -p inst-b logs -f openclaw-agent
```

Each instance gets independent state because `CONFIG_DIR` / `WORKSPACE_DIR` point at separate host paths (`agent/inst-b/...`), all gitignored. To keep the overrides persistent instead of typing them inline, put them in a per-instance env file and pass it with `--env-file` (e.g. `docker compose -p inst-b --env-file .env.inst-b up -d`).

Because each instance has its own `openclaw.json` (under its `CONFIG_DIR`), set that instance's `gateway.controlUi.allowedOrigins` to its own `AGENT_PORT` (e.g. `http://localhost:18791`) — otherwise its control UI won't load.

> **Heads-up:** the override variables only take effect for the `up` command that *creates* the container; for later `exec` / `logs` you just need the matching `-p`. If you forget to set `CONFIG_DIR` / `WORKSPACE_DIR` on `up`, the instance falls back to the shared default dirs and will clobber the primary instance's state.
