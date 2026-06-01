#!/usr/bin/env bash
set -euo pipefail

: "${DISPLAY:=:99}"
export DISPLAY
GEOM="${VNC_GEOMETRY:-1280x800x24}"

# Clean up a stale X lock/socket from a previous run so a container *restart*
# (which reuses the filesystem) can start Xvfb instead of looping on
# "Server is already active for display N". The entrypoint is the only thing
# that uses this display, so any lock found at startup is necessarily stale.
rm -f "/tmp/.X${DISPLAY#:}-lock" "/tmp/.X11-unix/X${DISPLAY#:}" 2>/dev/null || true

# Virtual display for the headed browser
Xvfb "$DISPLAY" -screen 0 "$GEOM" -nolisten tcp &

# Wait for the X socket before anything tries to use it
for _ in $(seq 1 50); do
  [ -e "/tmp/.X11-unix/X${DISPLAY#:}" ] && break
  sleep 0.1
done

# VNC auth: use a password if provided, otherwise refuse to start unauthenticated
PASSWD_FILE="$HOME/.vnc/passwd"
mkdir -p "$HOME/.vnc"
if [ -n "${VNC_PASSWORD:-}" ]; then
  x11vnc -storepasswd "$VNC_PASSWORD" "$PASSWD_FILE" >/dev/null 2>&1
else
  echo "with-novnc: VNC_PASSWORD is not set; refusing to expose an unauthenticated VNC server." >&2
  exit 1
fi

# VNC server bound to container-localhost only; websockify is the sole reachable bridge
x11vnc -display "$DISPLAY" -localhost -forever -shared -rfbport 5900 \
  -rfbauth "$PASSWD_FILE" -quiet -bg

# noVNC web client -> VNC
websockify --web=/usr/share/novnc 6080 localhost:5900 &

# Hand off to the image's real entrypoint/command (tini + openclaw gateway)
exec tini -s -- "$@"
