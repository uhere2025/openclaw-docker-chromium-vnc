FROM ghcr.io/openclaw/openclaw:latest
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      chromium fonts-liberation \
      xvfb x11vnc novnc websockify && \
    rm -rf /var/lib/apt/lists/*
COPY with-novnc.sh /usr/local/bin/with-novnc.sh
RUN chmod +x /usr/local/bin/with-novnc.sh
USER node
ENV OPENCLAW_BROWSER_EXECUTABLE=/usr/bin/chromium
ENV DISPLAY=:99
ENTRYPOINT ["/usr/local/bin/with-novnc.sh"]
CMD ["node", "openclaw.mjs", "gateway"]
