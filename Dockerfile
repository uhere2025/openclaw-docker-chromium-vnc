FROM ghcr.io/openclaw/openclaw:latest
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      chromium fonts-liberation \
      xvfb x11vnc novnc websockify python3 python3-pip && \
    rm -rf /var/lib/apt/lists/*

# Install your external Python dependencies here
RUN pip3 install --break-system-packages yfinance requests pandas numpy

# run this after making changes: docker compose up -d --build --force-recreate

COPY with-novnc.sh /usr/local/bin/with-novnc.sh
RUN chmod +x /usr/local/bin/with-novnc.sh
USER node
ENV OPENCLAW_BROWSER_EXECUTABLE=/usr/bin/chromium
ENV DISPLAY=:99
ENTRYPOINT ["/usr/local/bin/with-novnc.sh"]
CMD ["node", "openclaw.mjs", "gateway"]
