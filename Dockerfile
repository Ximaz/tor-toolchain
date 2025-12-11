FROM alpine:3.23.0 AS builder

WORKDIR /build

ARG TOR_VERSION="0.4.8.21"

ENV TOR_VERSION="${TOR_VERSION}"
ENV TOR_URL="https://gitlab.torproject.org/tpo/core/tor/-/archive/tor-${TOR_VERSION}/tor-${TOR_VERSION}.tar.gz"

RUN apk add curl

ENV TOR_FILE="tor-${TOR_VERSION}"
RUN curl --request GET "${TOR_URL}" \
    --location \
    --output "${TOR_FILE}"

RUN tar --strip-components=1 -x -f "${TOR_FILE}" -C . -p

RUN apk add automake \
    autoconf

RUN ./autogen.sh

RUN apk add build-base \
    libevent-dev \
    openssl-dev \
    zlib-dev

RUN ./configure --disable-asciidoc

RUN apk add make

RUN make -j4

RUN make install

RUN mkdir -p /build/binaries

RUN cp ./src/app/tor \
    ./src/tools/tor-resolve \
    ./src/tools/tor-print-ed-signing-cert \
    ./src/tools/tor-gencert \
    ./contrib/client-tools/torify \
    ./src/config/geoip \
    ./src/config/geoip6 \
    ./src/config/torrc.sample \
    /build/binaries

FROM alpine:3.23.0 AS tor-toolchain

RUN mkdir -p /usr/local/bin

RUN mkdir -p /usr/local/etc/tor

RUN mkdir -p /usr/local/share/tor

COPY --from=builder /build/binaries/tor /usr/local/bin/tor

COPY --from=builder /build/binaries/tor-resolve /usr/local/bin/tor-resolve

COPY --from=builder /build/binaries/tor-print-ed-signing-cert /usr/local/bin/tor-print-ed-signing-cert

COPY --from=builder /build/binaries/tor-gencert /usr/local/bin/tor-gencert

COPY --from=builder /build/binaries/torify /usr/local/bin/torify

COPY --from=builder /build/binaries/torrc.sample /usr/local/etc/tor/torrc.sample

COPY --from=builder /build/binaries/geoip /usr/local/share/tor/geoip

COPY --from=builder /build/binaries/geoip6 /usr/local/share/tor/geoip6

RUN apk add libevent \
    openssl \
    zlib
