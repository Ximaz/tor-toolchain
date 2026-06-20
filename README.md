# Tor Toolchain

This repository contains a Dockerfile that, once built, compiles all the Tor
project binaries. This is specially nice to have when wanting to use Tor as a
proxy locally without actually installing Tor binaries on your host.

The Tor source is downloaded from the official `https://dist.torproject.org/`
release server and its GPG signature is verified against the pinned Tor signing
keys during the build, so a tampered or corrupted tarball aborts the build.

## Usage

The `Dockerfile` located at the root of the project is responsible for building
the binaries.

It accepts a build parameter called `TOR_VERSION` which corresponds to a Tor
release version, as published on the official server:
`https://dist.torproject.org/`

`TOR_VERSION` is the **single source of truth** for the project and lives as the
default of the `ARG TOR_VERSION` declaration at the top of the `Dockerfile`
(currently `0.4.9.9`, the latest release as of today). To build a different
version, override it at build time:
```bash
docker build --build-arg TOR_VERSION=0.4.9.9 -t tor-toolchain .
```

For an easy build, there is a `docker-compose.yml` file which builds everything
for you. To build locally, use this command:
```bash
docker compose -f docker-compose.yml build
```

At the end, you should have a new image called `tor-toolchain`, from which you
can derive new Docker images in order to, let's say, use a custom `torrc` config.

## Pulling the published image

CI builds a multi-arch image (linux/amd64 + linux/arm64) and publishes it to the
GitHub Container Registry, tagged with `latest`, the Tor version, and the commit
SHA:
```bash
docker pull ghcr.io/ximaz/tor-toolchain/tor-toolchain:0.4.9.9
```

The published image is **keyless-signed with cosign** and ships an SBOM and build
provenance attestation. You can verify the signature with:
```bash
cosign verify ghcr.io/ximaz/tor-toolchain/tor-toolchain:0.4.9.9 \
  --certificate-identity-regexp 'https://github.com/ximaz/tor-toolchain/.github/workflows/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Tor Proxy

A `tor-proxy` Docker Compose service has been added which lets you set up a Tor
proxy locally easily. It is a `SOCKS5` proxy, reachable on port `9050`.

The service runs hardened by default: a non-root user, a read-only root
filesystem with a `tmpfs` data directory, dropped Linux capabilities,
`no-new-privileges`, a memory limit, and a healthcheck on the SOCKS port.

To start the proxy, use the following command:
```bash
docker compose -f docker-compose.yml up tor-proxy --build -d
```
The default `torrc` configuration can be modified at the root of the project to
satisfy your needs.

Once started, make sure it works fine before attempting anything else. First,
`docker compose ps` should report the container as `healthy`. Then use the
following command to ensure the proxy is reachable and works as expected:
```bash
curl -s -x socks5h://127.0.0.1:9050 https://check.torproject.org | \
grep "Congratulations. This browser is configured to use Tor." >/dev/null && \
echo "Protected." || echo "Careful, you are not protected."
```

If you see `Protected.`, your proxy is set up correctly and locally reachable. If
not, you should check the logs of the container, something is not working as
expected, thus you are not protected yet.

## Keeping Tor up to date

A scheduled workflow (`.github/workflows/check-tor-release.yml`) watches
`dist.torproject.org` weekly and opens a pull request bumping `TOR_VERSION` when
a newer stable release appears. The bump PR is built and signature-verified by CI
before it can be merged.

## License

This repository's packaging work (the `Dockerfile`, `docker-compose.yml`,
`torrc`, and CI workflows) is released under the [MIT License](LICENSE). The
compiled Tor binaries produced by the build remain governed by Tor's own license
(3-clause BSD); this project only packages upstream Tor and does not relicense it.
