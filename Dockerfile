FROM alpine:3.24.1 AS tor-toolchain-builder

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
    ./LICENSE \
    /build/binaries

# Lyrebird
FROM golang:1.26.5-alpine3.24 AS lyrebird-builder

WORKDIR /build

ARG LYREBIRD_VERSION="0.8.1"
ENV LYREBIRD_VERSION="${LYREBIRD_VERSION}"
ENV LYREBIRD_REPO="https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird.git"

ENV CGO_ENABLED=0 \
    GOFLAGS="-mod=readonly" \
    GOPROXY="https://proxy.golang.org,direct" \
    GOSUMDB="sum.golang.org"

RUN apk add --no-cache git gnupg

RUN set -eu; \
    GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; \
    gpg --batch --auto-key-locate nodefault,wkd --locate-keys \
      meskio@torproject.org shelikhoo@torproject.org cohosh@torproject.org \
    || gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys \
      07948FFA64160A425BCD27EAC732B1D1C28F4E2F \
      40BBCBED223F5EB2A03EF657D7D7A110ABC79A6C \
      5A618CE840883942BAF1334F009DE379FD9B7B90; \
    git -c advice.detachedHead=false clone --depth 1 \
      --branch "lyrebird-${LYREBIRD_VERSION}" "${LYREBIRD_REPO}" src; \
    git -C src verify-tag --raw "lyrebird-${LYREBIRD_VERSION}" 2>&1 | tee verify.log; \
    grep -q '^\[GNUPG:\] VALIDSIG' verify.log; \
    gpgconf --kill all; rm -rf "$GNUPGHOME" verify.log

ARG GO_CRYPTO_VERSION="v0.54.0"
ARG GO_NET_VERSION="v0.57.0"
ARG PION_INTERCEPTOR_VERSION="v0.1.46"
ARG PION_DTLS_VERSION="v3.1.5"
ARG CIRCL_VERSION="v1.6.4"
ARG EDWARDS25519_VERSION="v1.1.1"

RUN GOFLAGS="" go -C src get \
      "golang.org/x/crypto@${GO_CRYPTO_VERSION}" \
      "golang.org/x/net@${GO_NET_VERSION}" \
      "github.com/pion/interceptor@${PION_INTERCEPTOR_VERSION}" \
      "github.com/pion/dtls/v3@${PION_DTLS_VERSION}" \
      "github.com/cloudflare/circl@${CIRCL_VERSION}" \
      "filippo.io/edwards25519@${EDWARDS25519_VERSION}" && \
    GOFLAGS="" go -C src mod tidy

# The dependency set no longer matches the one upstream tested against, so run
# lyrebird's own test suite before trusting the binary.
RUN go -C src test ./...

RUN mkdir -p /build/binaries && go -C src build -trimpath \
    -ldflags="-s -w -X main.lyrebirdVersion=${LYREBIRD_VERSION}" \
    -o /build/binaries/lyrebird ./cmd/lyrebird

RUN chmod 0555 /build/binaries/lyrebird && /build/binaries/lyrebird --version

RUN cp src/LICENSE /build/binaries/LICENSE.lyrebird

FROM alpine:3.24.1 AS tor-toolchain

COPY --from=tor-toolchain-builder \
    /build/binaries/tor \
    /build/binaries/tor-resolve \
    /build/binaries/tor-print-ed-signing-cert \
    /build/binaries/tor-gencert \
    /build/binaries/torify \
    /usr/local/bin/

COPY --from=tor-toolchain-builder \
    /build/binaries/geoip \
    /build/binaries/geoip6 \
    /usr/local/share/tor/

COPY --from=tor-toolchain-builder /build/binaries/torrc.sample /usr/local/etc/tor/torrc.sample
COPY --from=tor-toolchain-builder /build/binaries/LICENSE /usr/local/share/licenses/tor/LICENSE

COPY --from=lyrebird-builder --chown=root:root --chmod=0555 \
    /build/binaries/lyrebird /usr/local/bin/lyrebird

COPY --from=lyrebird-builder /build/binaries/LICENSE.lyrebird /usr/local/share/licenses/lyrebird/LICENSE

COPY LICENSE NOTICE /usr/local/share/licenses/tor-toolchain/

RUN apk add --no-cache libevent openssl zlib

RUN addgroup -S -g 1000 tor && \
    adduser -S -D -H -h /var/lib/tor -G tor -u 1000 tor && \
    mkdir -p /var/lib/tor && \
    chown -R tor:tor /var/lib/tor && \
    chmod 700 /var/lib/tor

USER tor
