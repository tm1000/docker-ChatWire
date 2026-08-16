#build chatwire image
FROM golang:1.26.6 AS chatwire-builder

WORKDIR /src/ChatWire
COPY chatwire/ ./

RUN go build

# build factorio image
FROM debian:stable-slim

RUN apt-get -q update \
    && DEBIAN_FRONTEND=noninteractive apt-get -qy install jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /chatwire/factorio

COPY --from=chatwire-builder /src/ChatWire/ChatWire /bin/ChatWire
COPY docker-files/chatwire-entrypoint.sh /chatwire-entrypoint.sh
RUN chmod +x /chatwire-entrypoint.sh

WORKDIR /chatwire

#EXPOSE $PORT/udp $RCON_PORT/tcp
ENTRYPOINT ["/chatwire-entrypoint.sh"]