# =============================================================================
#  BONUS - "a service of your choice": a home-made health dashboard
# -----------------------------------------------------------------------------
#  Why this one: the whole point of Inception is that the stack has no single
#  place to look at. `docker ps` says a container is *running*, which is not the
#  same as *answering*. This service probes every dependency the way a client
#  would - a TCP connect, a redis PING, an FTP banner, an HTTP GET - and shows
#  one page with the answer. It is the first thing to open when something is
#  wrong, and it needs no access to the Docker socket to do it.
# =============================================================================
FROM debian:bookworm

# The full python3 package, not python3-minimal: -minimal deliberately omits
# most of the standard library (json, ssl, http.server are not in it).
# Standard library only all the same: no pip, no wheels, no network at build time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 \
 && rm -rf /var/lib/apt/lists/*

COPY app/server.py /opt/status/server.py

RUN useradd --system --no-create-home --shell /usr/sbin/nologin status
USER status

EXPOSE 5000

# -u keeps the logs unbuffered so `docker logs status` is live.
CMD ["python3", "-u", "/opt/status/server.py"]
