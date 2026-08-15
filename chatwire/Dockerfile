#build chatwire image
FROM golang:1.26.6 AS chatwire-builder

WORKDIR /src
RUN git clone https://github.com/M45-Science/ChatWire.git
WORKDIR /src/ChatWire

# ChatWire's cwlog package only writes to log files, never stdout, so
# `docker logs` shows nothing. Mirror each log line to stdout too.
# Guarded with a count check so an upstream change fails the build loudly
# instead of silently shipping unpatched.
RUN test "$(grep -c 'filepath.Base(filename), line, text)' cwlog/cwLog.go)" = "2" \
    && test "$(grep -c 'date, text)' cwlog/cwLog.go)" = "1" \
    && sed -i '/filepath.Base(filename), line, text)/a\    fmt.Print(buf)' cwlog/cwLog.go \
    && sed -i '/date, text)/a\    fmt.Print(buf)' cwlog/cwLog.go

RUN go build

# build factorio image
FROM debian:stable-slim

RUN apt-get -q update \
    && DEBIAN_FRONTEND=noninteractive apt-get -qy install jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /chatwire/factorio

COPY --from=chatwire-builder /src/ChatWire/ChatWire /bin/ChatWire
COPY files/chatwire-entrypoint.sh /chatwire-entrypoint.sh
RUN chmod +x /chatwire-entrypoint.sh

WORKDIR /chatwire

#EXPOSE $PORT/udp $RCON_PORT/tcp
ENTRYPOINT ["/chatwire-entrypoint.sh"]