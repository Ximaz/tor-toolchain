FROM alpine:3.24.1 AS builder

WORKDIR /build

# Single source of truth for the Tor version (overridable with --build-arg).
ARG TOR_VERSION="0.4.9.11"
ENV TOR_VERSION="${TOR_VERSION}"
ENV TOR_DIST="https://dist.torproject.org"

RUN apk add --no-cache \
    curl \
    gnupg \
    build-base \
    libevent-dev \
    openssl-dev \
    zlib-dev \
    make

RUN curl --fail-with-body --proto '=https' --tlsv1.2 --location \
    --retry 3 --retry-delay 2 -sS --remote-name-all \
    "${TOR_DIST}/tor-${TOR_VERSION}.tar.gz" \
    "${TOR_DIST}/tor-${TOR_VERSION}.tar.gz.sha256sum" \
    "${TOR_DIST}/tor-${TOR_VERSION}.tar.gz.sha256sum.asc"

RUN gpg --batch --auto-key-locate nodefault,wkd --locate-keys \
      ahf@torproject.org dgoulet@torproject.org nickm@torproject.org \
    || gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys \
      514102454D0A87DB0767A1EBBE6A0531C18A9179 \
      B74417EDDF22AC9F9E90F49142E86A2A11F48D36 \
      2133BC600AB133E1D826D173FE43009C4607B1FB

RUN gpg --batch --verify \
    "tor-${TOR_VERSION}.tar.gz.sha256sum.asc" \
    "tor-${TOR_VERSION}.tar.gz.sha256sum"
RUN sha256sum -c "tor-${TOR_VERSION}.tar.gz.sha256sum"

RUN tar --strip-components=1 -x -f "tor-${TOR_VERSION}.tar.gz" -C . -p

RUN ./configure --disable-asciidoc

RUN make -j"$(nproc)"

RUN strip --strip-all \
    ./src/app/tor \
    ./src/tools/tor-resolve \
    ./src/tools/tor-print-ed-signing-cert \
    ./src/tools/tor-gencert

RUN mkdir -p /build/binaries && cp \
    ./src/app/tor \
    ./src/tools/tor-resolve \
    ./src/tools/tor-print-ed-signing-cert \
    ./src/tools/tor-gencert \
    ./contrib/client-tools/torify \
    ./src/config/geoip \
    ./src/config/geoip6 \
    ./src/config/torrc.sample \
    /build/binaries

FROM alpine:3.24.1 AS tor-toolchain

COPY --from=builder \
    /build/binaries/tor \
    /build/binaries/tor-resolve \
    /build/binaries/tor-print-ed-signing-cert \
    /build/binaries/tor-gencert \
    /build/binaries/torify \
    /usr/local/bin/

COPY --from=builder \
    /build/binaries/geoip \
    /build/binaries/geoip6 \
    /usr/local/share/tor/

COPY --from=builder /build/binaries/torrc.sample /usr/local/etc/tor/torrc.sample

RUN apk add --no-cache libevent openssl zlib

RUN addgroup -S -g 1000 tor && \
    adduser -S -D -H -h /var/lib/tor -G tor -u 1000 tor && \
    mkdir -p /var/lib/tor && \
    chown -R tor:tor /var/lib/tor && \
    chmod 700 /var/lib/tor

USER tor
