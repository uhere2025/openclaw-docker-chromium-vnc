# Browser Tool Setup for the Agent (OpenClaw)

## Goal
Enable the OpenClaw browser tool for the Dockerized agent (arm64 host, local LM Studio models), and choose between a container browser vs. the host's browser.

## Investigation
- **Container had no browser** — the image ships the browser *plugin code* but no Chromium/Chrome binary.
- **Host has Brave 148** (Chromium-based) with a live display.
- **Container is arm64**; Debian bookworm provides Chromium 148 for arm64 in apt.

## Decision
**Install Chromium into the container** rather than attach to the host's Brave.

Reasons:
- The agent only does public research (no personal logins needed).
- Host remote-debugging CDP has no auth and would expose your real browser sessions.
- The container route stays isolated, reproducible, and runs native arm64.

## Changes made
| File | Change |
|---|---|
| `Dockerfile` (new) | Derives from the OpenClaw image; installs `chromium` + fonts; sets `OPENCLAW_BROWSER_EXECUTABLE`. |
| `docker-compose.yml` | `image:` → `build: .` |
| `agent/config/openclaw.json` | Added `browser` block (`enabled`, `headless`, `executablePath`, `noSandbox: true`) and `tools` block (`coding` profile + `alsoAllow: ["browser"]`). |

## Issues hit and fixed
1. **Invalid `ssrfPolicy: "public-only"`** — it's an object, not a string; caused a startup crash-loop. Removed it. The default already blocks private networks, which is the desired behavior.
2. **Sandbox error** in the container — added `noSandbox: true`.

## Verified working
- Built the image, recreated the container — healthy.
- Browser starts headless; opened `example.com`; captured a clean ARIA snapshot.
- **SSRF guard confirmed**: navigation to LM Studio host `192.168.1.111:1234` is `blocked by policy` — the agent can't reach the LAN.

## Notes for ongoing use
- Keep RSS/JSON work on the plain `urllib` scripts; use the browser only for JS-rendered pages, bot-walled sites, or screenshots/PDFs.
- Route screenshots to `gemma-4-26b` (has vision), not nemotron.
- `noSandbox` is acceptable inside this isolated, LAN-blocked container. To restore the sandbox later, add `chromium-sandbox` to the Dockerfile and drop the flag.

## Rebuild / restart commands
```bash
docker compose up -d --build              # rebuild image and recreate
docker exec openclaw-agent openclaw browser --browser-profile openclaw start
docker exec openclaw-agent openclaw browser --browser-profile openclaw open https://example.com
docker exec openclaw-agent openclaw browser --browser-profile openclaw snapshot
```
